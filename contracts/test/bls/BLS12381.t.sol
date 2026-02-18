// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {BLS12381} from "src/bls/libs/BLS12381.sol";

/**
 * @title BLS12381Test
 * @author Lay3r Labs
 * @notice Unit tests for the BLS12381 precompile wrapper library.
 */
contract BLS12381Test is Test {
    /* solhint-disable func-name-mixedcase */

    function test_PubkeyFromSecret() public view {
        uint256 sk = 42;
        bytes memory pubkey = BLS12381.pubkeyFromSecret(sk);
        assertEq(pubkey.length, BLS12381.G1_POINT_SIZE);
    }

    function test_G1Add() public view {
        // Generate two pubkeys and add them
        bytes memory pk1 = BLS12381.pubkeyFromSecret(1);
        bytes memory pk2 = BLS12381.pubkeyFromSecret(2);
        bytes memory sum = BLS12381.g1Add(pk1, pk2);
        assertEq(sum.length, BLS12381.G1_POINT_SIZE);

        // pk1 + pk2 should equal the pubkey for sk=3 (since G is a group generator)
        // This is only true if sk*G is homomorphic: (1+2)*G = 3*G
        bytes memory pk3 = BLS12381.pubkeyFromSecret(3);
        assertEq(keccak256(sum), keccak256(pk3));
    }

    function test_G2Add() public view {
        // Generate two G2 points via MSM and add them
        bytes memory g2gen = _getG2Point(1);
        bytes memory g2gen2 = _getG2Point(2);
        bytes memory sum = BLS12381.g2Add(g2gen, g2gen2);
        assertEq(sum.length, BLS12381.G2_POINT_SIZE);

        bytes memory g2gen3 = _getG2Point(3);
        assertEq(keccak256(sum), keccak256(g2gen3));
    }

    function test_PairingCheck_ValidSignature() public view {
        uint256 sk = 123;
        bytes memory pubkey = BLS12381.pubkeyFromSecret(sk);

        // Create a message point in G2 (use a simple hash)
        bytes memory messageG2 = _getG2Point(42);

        // Sign: sig = sk * messageG2
        bytes memory signature = BLS12381.sign(sk, messageG2);

        // Verify: e(pubkey, messageG2) * e(-G1gen, signature) == 1
        bool valid = BLS12381.verifyAggregateSignature(pubkey, messageG2, signature);
        assertTrue(valid);
    }

    function test_PairingCheck_InvalidSignature() public view {
        uint256 sk = 123;
        bytes memory pubkey = BLS12381.pubkeyFromSecret(sk);

        bytes memory messageG2 = _getG2Point(42);

        // Sign with a different key
        bytes memory wrongSignature = BLS12381.sign(456, messageG2);

        bool valid = BLS12381.verifyAggregateSignature(pubkey, messageG2, wrongSignature);
        assertFalse(valid);
    }

    function test_AggregateSignatures() public view {
        uint256 sk1 = 100;
        uint256 sk2 = 200;
        bytes memory pk1 = BLS12381.pubkeyFromSecret(sk1);
        bytes memory pk2 = BLS12381.pubkeyFromSecret(sk2);

        bytes memory messageG2 = _getG2Point(999);

        // Individual signatures
        bytes memory sig1 = BLS12381.sign(sk1, messageG2);
        bytes memory sig2 = BLS12381.sign(sk2, messageG2);

        // Aggregate pubkeys and signatures
        bytes memory aggPk = BLS12381.g1Add(pk1, pk2);
        bytes memory aggSig = BLS12381.g2Add(sig1, sig2);

        // Verify aggregate
        bool valid = BLS12381.verifyAggregateSignature(aggPk, messageG2, aggSig);
        assertTrue(valid);
    }

    function test_G1Msm_SinglePoint() public view {
        // G1MSM with single pair should equal pubkeyFromSecret
        uint256 sk = 77;
        bytes memory input = abi.encodePacked(BLS12381.G1_GENERATOR, bytes32(sk));
        bytes memory result = BLS12381.g1Msm(input);
        bytes memory expected = BLS12381.pubkeyFromSecret(sk);
        assertEq(keccak256(result), keccak256(expected));
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Get a G2 point by multiplying the G2 generator by a scalar.
    ///      We use the G2MSM precompile to generate test points.
    function _getG2Point(
        uint256 scalar
    ) internal view returns (bytes memory) {
        // G2 generator (standard BLS12-381 G2 generator point)
        // x = (x_c0, x_c1), y = (y_c0, y_c1) — each coordinate is 64 bytes
        // solhint-disable-next-line max-line-length
        bytes memory g2Generator =
            hex"00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb80000000000000000000000000000000013e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be";
        bytes memory input = abi.encodePacked(g2Generator, bytes32(scalar));
        return BLS12381.g2Msm(input);
    }
}
