// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BLS12381} from "./BLS12381.sol";

/// @title HashToCurve
/// @author Lay3r Labs
/// @notice Implements hash-to-curve for BLS12-381 G2 per RFC 9380 (section 8.8.2).
///         Suite: BLS12381G2_XMD:SHA-256_SSWU_RO_
library HashToCurve {
    // ──────────────────────────────────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev BLS12-381 base field prime p.
    bytes internal constant BLS_FIELD_MODULUS =
        hex"1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab";

    /// @dev Domain separation tag for BLS12381G2_XMD:SHA-256_SSWU_RO_.
    bytes internal constant DST = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_";

    /// @dev MODEXP precompile address.
    address internal constant MODEXP = address(0x05);

    /// @dev SHA-256 precompile address.
    address internal constant SHA256_PRECOMPILE = address(0x02);

    /// @dev The number of bytes output by expand_message_xmd (256 bytes for 4 Fp elements).
    uint256 internal constant EXPAND_LEN = 256;

    /// @dev SHA-256 block size in bytes.
    uint256 internal constant SHA256_BLOCK_SIZE = 64;

    /// @dev SHA-256 output size in bytes.
    uint256 internal constant SHA256_OUTPUT_SIZE = 32;

    /// @dev Each Fp element needs 64 bytes of pseudo-random input (512 bits -> reduced mod p).
    uint256 internal constant BYTES_PER_FP = 64;

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────
    error HashToCurveFailed();

    // ──────────────────────────────────────────────────────────────────────────
    // Main entry point
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Hash an arbitrary message to a point on the BLS12-381 G2 curve.
    /// @param message The message bytes to hash.
    /// @return The G2 curve point (256 bytes).
    function hashToCurveG2(
        bytes memory message
    ) internal view returns (bytes memory) {
        // Step 1: expand_message_xmd to get 256 pseudo-random bytes
        bytes memory pseudoRandomBytes = expandMsgXmd(message, DST, EXPAND_LEN);

        // Step 2: Hash to two Fp2 field elements
        (bytes memory u0, bytes memory u1) = hashToFieldFp2(pseudoRandomBytes);

        // Step 3: Map each Fp2 element to G2 via the precompile
        bytes memory Q0 = BLS12381.mapFp2ToG2(u0);
        bytes memory Q1 = BLS12381.mapFp2ToG2(u1);

        // Step 4: Add the two G2 points
        return BLS12381.g2Add(Q0, Q1);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // expand_message_xmd (RFC 9380, Section 5.3.1)
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Implements expand_message_xmd with SHA-256 per RFC 9380 Section 5.3.1.
    /// @param message The input message.
    /// @param dst The domain separation tag.
    /// @param lenInBytes The number of output bytes (must be <= 8160).
    /// @return The expanded pseudo-random bytes.
    function expandMsgXmd(
        bytes memory message,
        bytes memory dst,
        uint256 lenInBytes
    ) internal view returns (bytes memory) {
        uint256 ell = (lenInBytes + SHA256_OUTPUT_SIZE - 1) / SHA256_OUTPUT_SIZE;

        // DST_prime = DST || I2OSP(len(DST), 1)
        bytes memory dstPrime = abi.encodePacked(dst, uint8(dst.length));

        // msg_prime = Z_pad || msg || l_i_b_str || I2OSP(0, 1) || DST_prime
        // Z_pad is SHA256_BLOCK_SIZE zero bytes
        // l_i_b_str = I2OSP(len_in_bytes, 2)
        bytes memory msgPrime = abi.encodePacked(
            new bytes(SHA256_BLOCK_SIZE), // Z_pad
            message,
            uint16(lenInBytes), // l_i_b_str as 2 bytes big-endian
            uint8(0), // I2OSP(0, 1)
            dstPrime
        );

        // b_0 = H(msg_prime)
        bytes32 b0 = _sha256(msgPrime);

        // b_1 = H(b_0 || I2OSP(1, 1) || DST_prime)
        bytes memory uniform = new bytes(lenInBytes);
        bytes32 bi = _sha256(abi.encodePacked(b0, uint8(1), dstPrime));

        // Copy b_1 into output
        _copyBytes32(uniform, 0, bi);

        // For i = 2 to ell:
        //   b_i = H(strxor(b_0, b_{i-1}) || I2OSP(i, 1) || DST_prime)
        for (uint256 i = 2; i <= ell; ++i) {
            bytes32 xored = b0 ^ bi;
            bi = _sha256(abi.encodePacked(xored, uint8(i), dstPrime));
            uint256 offset = (i - 1) * SHA256_OUTPUT_SIZE;
            if (offset + SHA256_OUTPUT_SIZE <= lenInBytes) {
                _copyBytes32(uniform, offset, bi);
            } else {
                // Copy only remaining bytes
                uint256 remaining = lenInBytes - offset;
                for (uint256 j; j < remaining; ++j) {
                    uniform[offset + j] = bi[j];
                }
            }
        }

        return uniform;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Hash to Fp2 field elements
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Convert 256 pseudo-random bytes into two Fp2 field elements.
    ///         Each Fp2 = (Fp, Fp). Each Fp is derived from 64 pseudo-random bytes
    ///         reduced mod p via MODEXP(value, 1, p).
    /// @param pseudoRandomBytes 256 bytes of pseudo-random data.
    /// @return u0 First Fp2 element (128 bytes: two 64-byte Fp values).
    /// @return u1 Second Fp2 element (128 bytes: two 64-byte Fp values).
    function hashToFieldFp2(
        bytes memory pseudoRandomBytes
    ) internal view returns (bytes memory u0, bytes memory u1) {
        // Each Fp element is derived from 64 bytes of pseudo-random input
        // u0 = (e0_0, e0_1), u1 = (e1_0, e1_1)
        // pseudoRandomBytes layout: [e0_0(64) | e0_1(64) | e1_0(64) | e1_1(64)]
        bytes memory e0_0 = _sliceBytes(pseudoRandomBytes, 0, BYTES_PER_FP);
        bytes memory e0_1 = _sliceBytes(pseudoRandomBytes, BYTES_PER_FP, BYTES_PER_FP);
        bytes memory e1_0 = _sliceBytes(pseudoRandomBytes, 2 * BYTES_PER_FP, BYTES_PER_FP);
        bytes memory e1_1 = _sliceBytes(pseudoRandomBytes, 3 * BYTES_PER_FP, BYTES_PER_FP);

        // Reduce each 512-bit value mod p using MODEXP(value, 1, p)
        bytes memory r0_0 = _reduceModP(e0_0);
        bytes memory r0_1 = _reduceModP(e0_1);
        bytes memory r1_0 = _reduceModP(e1_0);
        bytes memory r1_1 = _reduceModP(e1_1);

        // Pack into Fp2 elements (each Fp is 64 bytes, left-padded)
        u0 = abi.encodePacked(r0_0, r0_1);
        u1 = abi.encodePacked(r1_0, r1_1);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Reduce a 512-bit (64-byte) value mod the BLS12-381 field prime p
    ///      using the MODEXP precompile: result = value^1 mod p.
    ///      Returns a 64-byte left-padded result (to match EIP-2537 Fp format).
    function _reduceModP(
        bytes memory value
    ) private view returns (bytes memory result) {
        // MODEXP input: [Bsize(32) | Esize(32) | Msize(32) | B(64) | E(1) | M(48)]
        uint256 baseLen = 64; // 512-bit input
        uint256 expLen = 1; // exponent = 1
        uint256 modLen = 48; // BLS12-381 p is 48 bytes

        bytes memory input = abi.encodePacked(
            uint256(baseLen),
            uint256(expLen),
            uint256(modLen),
            value, // 64 bytes base
            uint8(1), // exponent = 1
            BLS_FIELD_MODULUS // 48 bytes modulus
        );

        // MODEXP returns `modLen` bytes = 48 bytes
        bytes memory modexpResult = new bytes(48);
        bool success;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success :=
                staticcall(
                    gas(),
                    0x05, // MODEXP precompile
                    add(input, 0x20),
                    mload(input),
                    add(modexpResult, 0x20),
                    48
                )
        }
        if (!success) {
            revert HashToCurveFailed();
        }

        // Left-pad to 64 bytes (EIP-2537 Fp format: 16 zero bytes + 48 bytes)
        result = abi.encodePacked(bytes16(0), modexpResult);
    }

    /// @dev SHA-256 using the precompile at 0x02.
    function _sha256(
        bytes memory data
    ) private view returns (bytes32 h) {
        bool success;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success :=
                staticcall(gas(), 0x02, add(data, 0x20), mload(data), 0x00, 32)
            h := mload(0x00)
        }
        if (!success) {
            revert HashToCurveFailed();
        }
    }

    /// @dev Copy a bytes32 value into a bytes array at a given offset.
    function _copyBytes32(bytes memory dest, uint256 offset, bytes32 value) private pure {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(add(dest, 0x20), offset), value)
        }
    }

    /// @dev Slice `length` bytes from `data` starting at `start`.
    function _sliceBytes(
        bytes memory data,
        uint256 start,
        uint256 length
    ) private pure returns (bytes memory result) {
        result = new bytes(length);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let src := add(add(data, 0x20), start)
            let dst := add(result, 0x20)
            // Copy in 32-byte chunks
            for { let i := 0 } lt(i, length) { i := add(i, 0x20) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }
}
