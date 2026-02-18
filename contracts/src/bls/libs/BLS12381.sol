// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title BLS12381
/// @author Lay3r Labs
/// @notice Library for BLS12-381 operations using EIP-2537 precompiles.
library BLS12381 {
    // ──────────────────────────────────────────────────────────────────────────
    // EIP-2537 precompile addresses (Pectra-final)
    // ──────────────────────────────────────────────────────────────────────────
    address internal constant G1ADD = address(0x0b);
    address internal constant G1MSM = address(0x0c);
    address internal constant G2ADD = address(0x0d);
    address internal constant G2MSM = address(0x0e);
    address internal constant PAIRING_CHECK = address(0x0f);
    address internal constant MAP_FP2_TO_G2 = address(0x11);

    // ──────────────────────────────────────────────────────────────────────────
    // Size constants
    // ──────────────────────────────────────────────────────────────────────────
    uint256 internal constant G1_POINT_SIZE = 128;
    uint256 internal constant G2_POINT_SIZE = 256;
    uint256 internal constant SCALAR_SIZE = 32;
    uint256 internal constant FP_SIZE = 64;
    uint256 internal constant FP2_SIZE = 128;

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────
    error PrecompileCallFailed(address precompile);

    // ──────────────────────────────────────────────────────────────────────────
    // G1 generator and its negation
    //
    // Coordinates are 48-byte BLS12-381 Fp elements, left-padded to 64 bytes.
    //
    // G1 generator:
    //   x = 0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905
    //         a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb
    //   y = 0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af6
    //         00db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1
    //
    // Negated G1 generator (x, p - y):
    //   -y = 0x114d1d6855d545a8aa7d76c8cf2e21f267816aef1db507c9
    //          6655b9d5caac42364e6f38ba0ecb751bad54dcd6b939c2ca
    // ──────────────────────────────────────────────────────────────────────────

    // @dev Each coordinate is 128 hex chars: 32 hex zero-padding + 96 hex (48-byte Fp value)
    //      G1_GENERATOR = x(128 hex) || y(128 hex) = 256 hex chars = 128 bytes
    // solhint-disable-next-line max-line-length
    bytes internal constant G1_GENERATOR =
        hex"0000000000000000000000000000000017f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb0000000000000000000000000000000008b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1";

    // solhint-disable-next-line max-line-length
    bytes internal constant NEG_G1_GENERATOR =
        hex"0000000000000000000000000000000017f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb00000000000000000000000000000000114d1d6855d545a8aa7d76c8cf2e21f267816aef1db507c96655b9d5caac42364e6f38ba0ecb751bad54dcd6b939c2ca";

    // ──────────────────────────────────────────────────────────────────────────
    // Precompile wrappers
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Add two G1 points.
    /// @param p1 First G1 point (128 bytes).
    /// @param p2 Second G1 point (128 bytes).
    /// @return result The sum G1 point (128 bytes).
    function g1Add(
        bytes memory p1,
        bytes memory p2
    ) internal view returns (bytes memory result) {
        bytes memory input = abi.encodePacked(p1, p2);
        result = _callPrecompile(G1ADD, input, G1_POINT_SIZE);
    }

    /// @notice Multi-scalar multiplication in G1.
    /// @param input Concatenated (G1_point || scalar) pairs, each 160 bytes.
    /// @return result The resulting G1 point (128 bytes).
    function g1Msm(
        bytes memory input
    ) internal view returns (bytes memory result) {
        result = _callPrecompile(G1MSM, input, G1_POINT_SIZE);
    }

    /// @notice Add two G2 points.
    /// @param p1 First G2 point (256 bytes).
    /// @param p2 Second G2 point (256 bytes).
    /// @return result The sum G2 point (256 bytes).
    function g2Add(
        bytes memory p1,
        bytes memory p2
    ) internal view returns (bytes memory result) {
        bytes memory input = abi.encodePacked(p1, p2);
        result = _callPrecompile(G2ADD, input, G2_POINT_SIZE);
    }

    /// @notice Multi-scalar multiplication in G2.
    /// @param input Concatenated (G2_point || scalar) pairs, each 288 bytes.
    /// @return result The resulting G2 point (256 bytes).
    function g2Msm(
        bytes memory input
    ) internal view returns (bytes memory result) {
        result = _callPrecompile(G2MSM, input, G2_POINT_SIZE);
    }

    /// @notice Pairing check: verifies whether the product of pairings equals 1.
    /// @param input Concatenated (G1_point || G2_point) pairs, each 384 bytes.
    /// @return valid True if the pairing check passes.
    function pairingCheck(
        bytes memory input
    ) internal view returns (bool valid) {
        bytes memory output = _callPrecompile(PAIRING_CHECK, input, 32);
        valid = abi.decode(output, (uint256)) == 1;
    }

    /// @notice Map an Fp2 element to a G2 point (includes SWU + isogeny + cofactor clearing).
    /// @param fp2 The Fp2 element (128 bytes: two 64-byte Fp elements).
    /// @return result The G2 point (256 bytes).
    function mapFp2ToG2(
        bytes memory fp2
    ) internal view returns (bytes memory result) {
        result = _callPrecompile(MAP_FP2_TO_G2, fp2, G2_POINT_SIZE);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Aggregate signature verification
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Verify a BLS aggregate signature using the pairing equation:
    ///         e(aggregatedPubkey, messageG2) * e(-G1_gen, aggregateSignature) == 1
    /// @param aggregatedPubkey The aggregated G1 public key (128 bytes).
    /// @param messageG2 The message hashed to G2 (256 bytes).
    /// @param aggregateSignature The aggregate G2 signature (256 bytes).
    /// @return valid True if the signature is valid.
    function verifyAggregateSignature(
        bytes memory aggregatedPubkey,
        bytes memory messageG2,
        bytes memory aggregateSignature
    ) internal view returns (bool valid) {
        // Two-pair pairing check: e(apk, H(m)) * e(-G1gen, sig_agg) == 1
        bytes memory input = abi.encodePacked(
            aggregatedPubkey, // G1: 128 bytes
            messageG2, // G2: 256 bytes
            NEG_G1_GENERATOR, // G1: 128 bytes
            aggregateSignature // G2: 256 bytes
        );
        valid = pairingCheck(input);
    }

    /// @notice Compute a public key from a secret key: pubkey = sk * G1_generator.
    /// @param sk The secret key scalar (32 bytes, big-endian).
    /// @return pubkey The G1 public key (128 bytes).
    function pubkeyFromSecret(
        uint256 sk
    ) internal view returns (bytes memory pubkey) {
        bytes memory input = abi.encodePacked(G1_GENERATOR, bytes32(sk));
        pubkey = g1Msm(input);
    }

    /// @notice Sign a message (already mapped to G2) with a secret key: sig = sk * messageG2.
    /// @param sk The secret key scalar.
    /// @param messageG2 The message point in G2 (256 bytes).
    /// @return signature The G2 signature (256 bytes).
    function sign(
        uint256 sk,
        bytes memory messageG2
    ) internal view returns (bytes memory signature) {
        bytes memory input = abi.encodePacked(messageG2, bytes32(sk));
        signature = g2Msm(input);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Call an EIP-2537 precompile via staticcall.
    function _callPrecompile(
        address precompile,
        bytes memory input,
        uint256 outputSize
    ) private view returns (bytes memory output) {
        output = new bytes(outputSize);
        bool success;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success := staticcall(
                gas(),
                precompile,
                add(input, 0x20), // skip length prefix
                mload(input), // input length
                add(output, 0x20), // skip length prefix
                outputSize
            )
        }
        if (!success) {
            revert PrecompileCallFailed(precompile);
        }
    }
}
