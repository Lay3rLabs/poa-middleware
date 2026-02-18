// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {HashToCurve} from "src/bls/libs/HashToCurve.sol";
import {BLS12381} from "src/bls/libs/BLS12381.sol";

/**
 * @title HashToCurveTest
 * @author Lay3r Labs
 * @notice Unit tests for the HashToCurve library.
 */
contract HashToCurveTest is Test {
    /* solhint-disable func-name-mixedcase */

    function test_HashToCurveG2_ReturnsValidG2Point() public view {
        bytes memory message = "test message";
        bytes memory point = HashToCurve.hashToCurveG2(message);
        assertEq(point.length, BLS12381.G2_POINT_SIZE);
    }

    function test_HashToCurveG2_DifferentMessagesProduceDifferentPoints() public view {
        bytes memory point1 = HashToCurve.hashToCurveG2("message A");
        bytes memory point2 = HashToCurve.hashToCurveG2("message B");
        assertTrue(keccak256(point1) != keccak256(point2));
    }

    function test_HashToCurveG2_SameMessageProducesSamePoint() public view {
        bytes memory point1 = HashToCurve.hashToCurveG2("deterministic");
        bytes memory point2 = HashToCurve.hashToCurveG2("deterministic");
        assertEq(keccak256(point1), keccak256(point2));
    }

    function test_HashToCurveG2_EmptyMessage() public view {
        bytes memory point = HashToCurve.hashToCurveG2("");
        assertEq(point.length, BLS12381.G2_POINT_SIZE);
    }

    function test_HashToCurveG2_LongMessage() public view {
        // Test with a message longer than SHA-256 block size
        bytes memory longMsg = new bytes(200);
        for (uint256 i; i < 200; ++i) {
            longMsg[i] = bytes1(uint8(i % 256));
        }
        bytes memory point = HashToCurve.hashToCurveG2(longMsg);
        assertEq(point.length, BLS12381.G2_POINT_SIZE);
    }

    function test_ExpandMsgXmd_OutputLength() public view {
        bytes memory msg_ = "test";
        bytes memory dst = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_";
        bytes memory output = HashToCurve.expandMsgXmd(msg_, dst, 256);
        assertEq(output.length, 256);
    }

    function test_ExpandMsgXmd_Deterministic() public view {
        bytes memory dst = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_";
        bytes memory out1 = HashToCurve.expandMsgXmd("hello", dst, 128);
        bytes memory out2 = HashToCurve.expandMsgXmd("hello", dst, 128);
        assertEq(keccak256(out1), keccak256(out2));
    }

    function test_ExpandMsgXmd_DifferentInputsDifferentOutputs() public view {
        bytes memory dst = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_";
        bytes memory out1 = HashToCurve.expandMsgXmd("hello", dst, 128);
        bytes memory out2 = HashToCurve.expandMsgXmd("world", dst, 128);
        assertTrue(keccak256(out1) != keccak256(out2));
    }

    function test_HashToFieldFp2_OutputSizes() public view {
        // Generate 256 pseudo-random bytes first
        bytes memory dst = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_";
        bytes memory pseudoRandomBytes = HashToCurve.expandMsgXmd("test", dst, 256);
        (bytes memory u0, bytes memory u1) = HashToCurve.hashToFieldFp2(pseudoRandomBytes);
        // Each Fp2 is 128 bytes (two 64-byte Fp elements)
        assertEq(u0.length, BLS12381.FP2_SIZE);
        assertEq(u1.length, BLS12381.FP2_SIZE);
    }

    function test_HashToCurveG2_SignatureRoundtrip() public view {
        // Full roundtrip: hash a message to G2, sign with a key, verify
        uint256 sk = 12_345;
        bytes memory pubkey = BLS12381.pubkeyFromSecret(sk);

        bytes32 digest = keccak256("signed message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(abi.encodePacked(digest));

        bytes memory signature = BLS12381.sign(sk, messageG2);

        bool valid = BLS12381.verifyAggregateSignature(pubkey, messageG2, signature);
        assertTrue(valid);
    }
}
