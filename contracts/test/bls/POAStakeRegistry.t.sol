// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IWavsServiceManager} from "../../src/bls/interfaces/IWavsServiceManager.sol";
import {IWavsServiceHandler} from "../../src/bls/interfaces/IWavsServiceHandler.sol";

import {POAStakeRegistry} from "src/bls/POAStakeRegistry.sol";
import {IPOAStakeRegistryErrors} from "src/bls/interfaces/IPOAStakeRegistry.sol";
import {BLS12381} from "src/bls/libs/BLS12381.sol";
import {HashToCurve} from "src/bls/libs/HashToCurve.sol";
import {UpgradeableProxyLib} from "script/bls/utils/UpgradeableProxyLib.sol";

/**
 * @title POAStakeRegistryTest
 * @author Lay3r Labs
 * @notice Comprehensive unit tests for the BLS POAStakeRegistry contract
 */
contract POAStakeRegistryTest is Test {
    /* solhint-disable func-name-mixedcase, use-natspec */
    POAStakeRegistry public poaStakeRegistry;

    // Test addresses
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public nonOperator;

    // BLS secret keys (arbitrary scalars for testing)
    uint256 public constant SK1 = 111;
    uint256 public constant SK2 = 222;
    uint256 public constant SK3 = 333;

    // BLS public keys (derived in setUp)
    bytes public blsPk1;
    bytes public blsPk2;
    bytes public blsPk3;

    // Test values
    uint256 public constant INITIAL_THRESHOLD_WEIGHT = 1000;
    uint256 public constant INITIAL_QUORUM_NUMERATOR = 2;
    uint256 public constant INITIAL_QUORUM_DENOMINATOR = 3;
    uint256 public constant OPERATOR_WEIGHT_1 = 1000;
    uint256 public constant OPERATOR_WEIGHT_2 = 2000;
    uint256 public constant OPERATOR_WEIGHT_3 = 1500;

    // Events to test
    event OperatorRegistered(address indexed operator);
    event OperatorDeregistered(address indexed operator);
    event OperatorWeightUpdated(
        address indexed operator,
        uint256 oldWeight,
        uint256 newWeight
    );
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);
    event ThresholdWeightUpdated(uint256 thresholdWeight);
    event QuorumThresholdUpdated(
        uint256 indexed numerator,
        uint256 indexed denominator
    );
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        bytes32 indexed newKeyHash,
        bytes32 oldKeyHash
    );
    event ServiceURIUpdated(string serviceuri);

    function setUp() public {
        // Create test accounts
        owner = makeAddr("owner");
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        operator3 = makeAddr("operator3");
        nonOperator = makeAddr("nonOperator");

        // Derive BLS public keys from secret keys
        blsPk1 = BLS12381.pubkeyFromSecret(SK1);
        blsPk2 = BLS12381.pubkeyFromSecret(SK2);
        blsPk3 = BLS12381.pubkeyFromSecret(SK3);

        // Deploy the contract
        vm.startPrank(owner);
        address poaStakeRegistryProxy = UpgradeableProxyLib.setUpEmptyProxy(owner);
        address poaStakeRegistryImpl = address(new POAStakeRegistry());

        bytes memory poaStakeRegistryInvalidUpgradeCall = abi.encodeCall(
            POAStakeRegistry.initialize,
            (
                address(0),
                INITIAL_THRESHOLD_WEIGHT,
                INITIAL_QUORUM_NUMERATOR,
                INITIAL_QUORUM_DENOMINATOR
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidAddressZero.selector
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            poaStakeRegistryProxy,
            poaStakeRegistryImpl,
            poaStakeRegistryInvalidUpgradeCall
        );

        bytes memory poaStakeRegistryUpgradeCall = abi.encodeCall(
            POAStakeRegistry.initialize,
            (
                owner,
                INITIAL_THRESHOLD_WEIGHT,
                INITIAL_QUORUM_NUMERATOR,
                INITIAL_QUORUM_DENOMINATOR
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            poaStakeRegistryProxy,
            poaStakeRegistryImpl,
            poaStakeRegistryUpgradeCall
        );
        poaStakeRegistry = POAStakeRegistry(poaStakeRegistryProxy);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Initialization
    // ══════════════════════════════════════════════════════════════════════════

    function test_Initialization() public view {
        assertEq(
            poaStakeRegistry.getLastCheckpointThresholdWeight(),
            INITIAL_THRESHOLD_WEIGHT
        );
        (uint256 numerator, uint256 denominator) = poaStakeRegistry
            .getLastCheckpointQuorum();
        assertEq(numerator, INITIAL_QUORUM_NUMERATOR);
        assertEq(denominator, INITIAL_QUORUM_DENOMINATOR);
        assertEq(poaStakeRegistry.owner(), owner);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Operator registration
    // ══════════════════════════════════════════════════════════════════════════

    function test_RegisterOperator() public {
        vm.startPrank(owner);

        vm.expectEmit(true, false, false, true);
        emit OperatorRegistered(operator1);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        assertTrue(poaStakeRegistry.operatorRegistered(operator1));
        assertEq(
            poaStakeRegistry.getOperatorWeight(operator1),
            OPERATOR_WEIGHT_1
        );
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1
        );

        vm.stopPrank();
    }

    function test_RegisterOperator_InvalidWeight() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidWeight.selector
            )
        );
        poaStakeRegistry.registerOperator(operator1, 0);
        vm.stopPrank();
    }

    function test_RegisterOperator_AlreadyRegistered() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.OperatorAlreadyRegistered.selector
            )
        );
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_2);

        vm.stopPrank();
    }

    function test_RegisterOperator_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Operator deregistration
    // ══════════════════════════════════════════════════════════════════════════

    function test_DeregisterOperator() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        vm.expectEmit(true, false, false, true);
        emit OperatorDeregistered(operator1);

        poaStakeRegistry.deregisterOperator(operator1);

        assertFalse(poaStakeRegistry.operatorRegistered(operator1));
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), 0);
        assertEq(poaStakeRegistry.getLastCheckpointTotalWeight(), 0);

        vm.stopPrank();
    }

    function test_DeregisterOperator_NotRegistered() public {
        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.OperatorNotRegistered.selector
            )
        );
        poaStakeRegistry.deregisterOperator(operator1);

        vm.stopPrank();
    }

    function test_DeregisterOperator_OnlyOwner() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.deregisterOperator(operator1);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Weight updates
    // ══════════════════════════════════════════════════════════════════════════

    function test_UpdateOperatorWeight() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        uint256 newWeight = OPERATOR_WEIGHT_1 + 500;

        vm.expectEmit(true, false, false, true);
        emit OperatorWeightUpdated(operator1, OPERATOR_WEIGHT_1, newWeight);

        poaStakeRegistry.updateOperatorWeight(operator1, newWeight);

        assertEq(poaStakeRegistry.getOperatorWeight(operator1), newWeight);
        assertEq(poaStakeRegistry.getLastCheckpointTotalWeight(), newWeight);

        vm.stopPrank();
    }

    function test_UpdateOperatorWeight_OnlyOwner() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_2);
    }

    function test_UpdateOperatorWeight_NotRegistered() public {
        vm.startPrank(owner);
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_1);
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), 0);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Threshold weight updates
    // ══════════════════════════════════════════════════════════════════════════

    function test_UpdateStakeThreshold() public {
        vm.startPrank(owner);

        uint256 newThreshold = INITIAL_THRESHOLD_WEIGHT + 500;

        vm.expectEmit(false, false, false, true);
        emit ThresholdWeightUpdated(newThreshold);

        poaStakeRegistry.updateStakeThreshold(newThreshold);

        assertEq(
            poaStakeRegistry.getLastCheckpointThresholdWeight(),
            newThreshold
        );

        vm.stopPrank();
    }

    function test_UpdateStakeThreshold_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.updateStakeThreshold(1500);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Quorum updates
    // ══════════════════════════════════════════════════════════════════════════

    function test_UpdateQuorum() public {
        vm.startPrank(owner);

        uint256 newNumerator = 3;
        uint256 newDenominator = 4;

        vm.expectEmit(false, false, false, true);
        emit QuorumThresholdUpdated(newNumerator, newDenominator);

        poaStakeRegistry.updateQuorum(newNumerator, newDenominator);

        (uint256 numerator, uint256 denominator) = poaStakeRegistry
            .getLastCheckpointQuorum();
        assertEq(numerator, newNumerator);
        assertEq(denominator, newDenominator);

        vm.stopPrank();
    }

    function test_UpdateQuorum_InvalidQuorum() public {
        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidQuorum.selector
            )
        );
        poaStakeRegistry.updateQuorum(1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidQuorum.selector
            )
        );
        poaStakeRegistry.updateQuorum(5, 3);

        vm.stopPrank();
    }

    function test_UpdateQuorum_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.updateQuorum(3, 4);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // BLS signing key updates
    // ══════════════════════════════════════════════════════════════════════════

    function test_UpdateOperatorSigningKey() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);

        bytes32 newKeyHash = keccak256(blsPk1);
        vm.expectEmit(true, true, true, true);
        emit SigningKeyUpdate(
            operator1,
            block.number,
            newKeyHash,
            bytes32(0)
        );

        _updateOperatorSigningKey(operator1, SK1, blsPk1);

        bytes memory storedKey = poaStakeRegistry.getLatestOperatorSigningKey(
            operator1
        );
        assertEq(keccak256(storedKey), keccak256(blsPk1));

        vm.stopPrank();
    }

    function test_UpdateOperatorSigningKey_NotRegistered() public {
        // Call contract directly to avoid precompile calls in test helper consuming vm.prank
        vm.prank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.OperatorNotRegistered.selector
            )
        );
        poaStakeRegistry.updateOperatorSigningKey(blsPk1, new bytes(256));
    }

    function test_UpdateOperatorSigningKey_OnlyOperator() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        // Call contract directly to avoid precompile calls in test helper consuming vm.prank
        vm.prank(nonOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.OperatorNotRegistered.selector
            )
        );
        poaStakeRegistry.updateOperatorSigningKey(blsPk1, new bytes(256));
    }

    function test_UpdateOperatorSigningKey_SameKey() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);

        // Same key should be a no-op
        _updateOperatorSigningKey(operator1, SK1, blsPk1);

        bytes memory storedKey = poaStakeRegistry.getLatestOperatorSigningKey(
            operator1
        );
        assertEq(keccak256(storedKey), keccak256(blsPk1));

        vm.stopPrank();
    }

    function test_UpdateOperatorSigningKey_InvalidKeyLength() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidBLSKeyLength.selector
            )
        );
        poaStakeRegistry.updateOperatorSigningKey(
            hex"0011", // wrong length
            new bytes(256)
        );
        vm.stopPrank();
    }

    function test_UpdateOperatorSigningKey_InvalidSigLength() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidBLSSignatureLength.selector
            )
        );
        poaStakeRegistry.updateOperatorSigningKey(
            blsPk1,
            hex"0011" // wrong length
        );
        vm.stopPrank();
    }

    function test_UpdateOperatorSigningKey_KeyAlreadyAssigned() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        // Operator 1 sets signing key
        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        // Operator 2 tries to use the same key — generate proof outside prank
        bytes32 messageHash = keccak256(abi.encode(operator2));
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(messageHash)
        );
        bytes memory blsSigProof = BLS12381.sign(SK1, messageG2);

        vm.prank(operator2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.SigningKeyAlreadyAssigned.selector
            )
        );
        poaStakeRegistry.updateOperatorSigningKey(blsPk1, blsSigProof);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Service URI
    // ══════════════════════════════════════════════════════════════════════════

    function test_SetServiceURI() public {
        vm.startPrank(owner);

        string memory newuri = "https://example.com/service";
        vm.expectEmit(false, false, false, true);
        emit ServiceURIUpdated(newuri);

        poaStakeRegistry.setServiceURI(newuri);

        assertEq(poaStakeRegistry.getServiceURI(), newuri);

        vm.stopPrank();
    }

    function test_SetServiceURI_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.setServiceURI("https://example.com/service");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // WAVS Service Manager interface
    // ══════════════════════════════════════════════════════════════════════════

    function test_GetAllocationManager() public view {
        assertEq(poaStakeRegistry.getAllocationManager(), address(0));
    }

    function test_GetDelegationManager() public view {
        assertEq(poaStakeRegistry.getDelegationManager(), address(0));
    }

    function test_GetStakeRegistry() public view {
        assertEq(poaStakeRegistry.getStakeRegistry(), address(0));
    }

    function test_GetLatestOperatorForSigningKey() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 keyHash = keccak256(blsPk1);
        assertEq(
            poaStakeRegistry.getLatestOperatorForSigningKey(keyHash),
            operator1
        );
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Historical data
    // ══════════════════════════════════════════════════════════════════════════

    function test_GetOperatorSigningKeyAtBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        _advanceBlocks(10);
        _updateOperatorSigningKey(operator1, SK2, blsPk2);
        vm.stopPrank();

        // Test current state
        bytes memory currentKey = poaStakeRegistry.getLatestOperatorSigningKey(
            operator1
        );
        assertEq(keccak256(currentKey), keccak256(blsPk2));

        // Test historical data
        bytes memory historicalKey = poaStakeRegistry
            .getOperatorSigningKeyAtBlock(operator1, uint32(block.number - 1));
        assertEq(keccak256(historicalKey), keccak256(blsPk1));
    }

    function test_GetOperatorWeightAtBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        _advanceBlocks(10);
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        assertEq(
            poaStakeRegistry.getOperatorWeight(operator1),
            OPERATOR_WEIGHT_2
        );
        assertEq(
            poaStakeRegistry.getOperatorWeightAtBlock(
                operator1,
                uint32(block.number - 1)
            ),
            OPERATOR_WEIGHT_1
        );
    }

    function test_GetTotalWeightAtBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        _advanceBlocks(10);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2
        );
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeightAtBlock(
                uint32(block.number - 1)
            ),
            OPERATOR_WEIGHT_1
        );
    }

    function test_GetThresholdWeightAtBlock() public {
        vm.startPrank(owner);
        _advanceBlocks(10);
        poaStakeRegistry.updateStakeThreshold(1500);
        vm.stopPrank();

        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), 1500);
        assertEq(
            poaStakeRegistry.getLastCheckpointThresholdWeightAtBlock(
                uint32(block.number - 1)
            ),
            INITIAL_THRESHOLD_WEIGHT
        );
    }

    function test_GetQuorumAtBlock() public {
        vm.startPrank(owner);
        _advanceBlocks(10);
        poaStakeRegistry.updateQuorum(3, 4);
        vm.stopPrank();

        (uint256 num, uint256 den) = poaStakeRegistry
            .getLastCheckpointQuorum();
        assertEq(num, 3);
        assertEq(den, 4);

        (uint256 histNum, uint256 histDen) = poaStakeRegistry
            .getLastCheckpointQuorumAtBlock(uint32(block.number - 1));
        assertEq(histNum, INITIAL_QUORUM_NUMERATOR);
        assertEq(histDen, INITIAL_QUORUM_DENOMINATOR);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // BLS Signature validation
    // ══════════════════════════════════════════════════════════════════════════

    function test_IsValidSignature_SingleSigner() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        bytes memory sig = BLS12381.sign(SK1, messageG2);

        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            sig,
            uint32(block.number - 1)
        );

        bytes4 result = poaStakeRegistry.isValidSignature(
            digest,
            signatureData
        );
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function test_IsValidSignature_TwoSigners() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        vm.startPrank(operator2);
        _updateOperatorSigningKey(operator2, SK2, blsPk2);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );

        // Sign with both keys
        bytes memory sig1 = BLS12381.sign(SK1, messageG2);
        bytes memory sig2 = BLS12381.sign(SK2, messageG2);
        bytes memory aggSig = BLS12381.g2Add(sig1, sig2);

        // Sort pubkeys by keyHash ascending
        bytes32 kh1 = keccak256(blsPk1);
        bytes32 kh2 = keccak256(blsPk2);

        bytes[] memory signerPubkeys = new bytes[](2);
        if (kh1 < kh2) {
            signerPubkeys[0] = blsPk1;
            signerPubkeys[1] = blsPk2;
        } else {
            signerPubkeys[0] = blsPk2;
            signerPubkeys[1] = blsPk1;
        }

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            aggSig,
            uint32(block.number - 1)
        );

        bytes4 result = poaStakeRegistry.isValidSignature(
            digest,
            signatureData
        );
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function test_IsValidSignature_InvalidLength() public {
        bytes32 digest = keccak256("test message");
        bytes[] memory signerPubkeys = new bytes[](0);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            new bytes(256),
            uint32(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidLength.selector
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InvalidReferenceBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        bytes memory signatureData = abi.encode(
            signerPubkeys,
            new bytes(256),
            uint32(block.number) // current block = invalid
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidReferenceBlock.selector
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_NotSorted() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        vm.startPrank(operator2);
        _updateOperatorSigningKey(operator2, SK2, blsPk2);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        bytes memory sig1 = BLS12381.sign(SK1, messageG2);
        bytes memory sig2 = BLS12381.sign(SK2, messageG2);
        bytes memory aggSig = BLS12381.g2Add(sig1, sig2);

        // Put pubkeys in WRONG order (reverse sorted)
        bytes32 kh1 = keccak256(blsPk1);
        bytes32 kh2 = keccak256(blsPk2);

        bytes[] memory signerPubkeys = new bytes[](2);
        if (kh1 < kh2) {
            // Wrong order: put larger first
            signerPubkeys[0] = blsPk2;
            signerPubkeys[1] = blsPk1;
        } else {
            signerPubkeys[0] = blsPk1;
            signerPubkeys[1] = blsPk2;
        }

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            aggSig,
            uint32(block.number - 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.NotSorted.selector
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InsufficientSignedStake() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, 100); // Low weight
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        bytes memory sig = BLS12381.sign(SK1, messageG2);

        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            sig,
            uint32(block.number - 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InsufficientSignedStake.selector
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InsufficientQuorum() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        poaStakeRegistry.updateQuorum(9, 10); // 90% quorum
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        bytes memory sig = BLS12381.sign(SK1, messageG2);

        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            sig,
            uint32(block.number - 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IWavsServiceManager.InsufficientQuorum.selector,
                1000,
                9,
                3000
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InvalidBLSSignature() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        // Sign with wrong key
        bytes memory wrongSig = BLS12381.sign(SK2, messageG2);

        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        _advanceBlocks(1);
        bytes memory signatureData = abi.encode(
            signerPubkeys,
            wrongSig,
            uint32(block.number - 1)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidBLSSignature.selector
            )
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // WAVS envelope validation
    // ══════════════════════════════════════════════════════════════════════════

    function test_Validate_ValidEnvelope() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, SK1, blsPk1);
        vm.stopPrank();

        IWavsServiceHandler.Envelope memory envelope = IWavsServiceHandler
            .Envelope({
                eventId: bytes20(uint160(1)),
                ordering: bytes12(0),
                payload: "test123"
            });

        bytes32 digest = keccak256(abi.encode(envelope));
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(digest)
        );
        bytes memory sig = BLS12381.sign(SK1, messageG2);

        bytes[] memory signerPubkeys = new bytes[](1);
        signerPubkeys[0] = blsPk1;

        _advanceBlocks(1);
        IWavsServiceHandler.SignatureData memory signatureData = IWavsServiceHandler
            .SignatureData({
                signerPubkeys: signerPubkeys,
                aggregateSignature: sig,
                referenceBlock: uint32(block.number - 1)
            });

        // This should not revert
        poaStakeRegistry.validate(envelope, signatureData);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Multiple operators weight calculations
    // ══════════════════════════════════════════════════════════════════════════

    function test_MultipleOperators_WeightCalculation() public {
        vm.startPrank(owner);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1
        );

        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2
        );

        poaStakeRegistry.registerOperator(operator3, OPERATOR_WEIGHT_3);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + OPERATOR_WEIGHT_3
        );

        poaStakeRegistry.deregisterOperator(operator2);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_3
        );

        vm.stopPrank();
    }

    function test_HistoricalData_Consistency() public {
        vm.startPrank(owner);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        _advanceBlocks(1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        _advanceBlocks(1);
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_1 + 500);
        _advanceBlocks(1);

        vm.stopPrank();

        uint256 actualTotalWeight = poaStakeRegistry
            .getLastCheckpointTotalWeight();
        assertEq(actualTotalWeight, OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + 500);

        assertEq(
            poaStakeRegistry.getOperatorWeight(operator1),
            OPERATOR_WEIGHT_1 + 500
        );
        assertEq(
            poaStakeRegistry.getOperatorWeight(operator2),
            OPERATOR_WEIGHT_2
        );

        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeightAtBlock(
                uint32(block.number - 1)
            ),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + 500
        );
    }

    function test_InputParametersInvalid() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidThresholdWeight.selector
            )
        );
        poaStakeRegistry.updateStakeThreshold(0);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidAddressZero.selector
            )
        );
        poaStakeRegistry.deregisterOperator(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidAddressZero.selector
            )
        );
        poaStakeRegistry.registerOperator(address(0), OPERATOR_WEIGHT_1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidWeight.selector
            )
        );
        poaStakeRegistry.updateOperatorWeight(
            operator1,
            uint256(type(uint160).max) + 1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPOAStakeRegistryErrors.InvalidAddressZero.selector
            )
        );
        poaStakeRegistry.updateOperatorWeight(address(0), OPERATOR_WEIGHT_1);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Gas optimization
    // ══════════════════════════════════════════════════════════════════════════

    function test_GasOptimization_MultipleUpdates() public {
        vm.startPrank(owner);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        poaStakeRegistry.registerOperator(operator3, OPERATOR_WEIGHT_3);

        poaStakeRegistry.updateOperatorWeight(
            operator1,
            OPERATOR_WEIGHT_1 + 100
        );
        poaStakeRegistry.updateOperatorWeight(
            operator2,
            OPERATOR_WEIGHT_2 + 200
        );

        poaStakeRegistry.updateStakeThreshold(2000);
        poaStakeRegistry.updateQuorum(3, 4);

        vm.stopPrank();

        uint256 expectedWeight = OPERATOR_WEIGHT_1 +
            OPERATOR_WEIGHT_2 +
            OPERATOR_WEIGHT_3 +
            100 +
            200;
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            expectedWeight
        );
        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), 2000);
        (uint256 num, uint256 den) = poaStakeRegistry
            .getLastCheckpointQuorum();
        assertEq(num, 3);
        assertEq(den, 4);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ══════════════════════════════════════════════════════════════════════════

    function _updateOperatorSigningKey(
        address operator,
        uint256 sk,
        bytes memory blsPk
    ) internal {
        // Generate BLS proof of key ownership
        bytes32 messageHash = keccak256(abi.encode(operator));
        bytes memory messageG2 = HashToCurve.hashToCurveG2(
            abi.encodePacked(messageHash)
        );
        bytes memory blsSigProof = BLS12381.sign(sk, messageG2);

        poaStakeRegistry.updateOperatorSigningKey(blsPk, blsSigProof);
    }

    function _advanceBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }
}
