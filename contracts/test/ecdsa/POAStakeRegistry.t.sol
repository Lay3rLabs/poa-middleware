// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IWavsServiceManager} from "@wavs/src/eigenlayer/ecdsa/interfaces/IWavsServiceManager.sol";
import {IWavsServiceHandler} from "@wavs/src/eigenlayer/ecdsa/interfaces/IWavsServiceHandler.sol";
import {Vm} from "forge-std/Vm.sol";

import {POAStakeRegistry} from "src/ecdsa/POAStakeRegistry.sol";
import {IPOAStakeRegistryErrors} from "src/ecdsa/interfaces/IPOAStakeRegistry.sol";
import {UpgradeableProxyLib} from "script/ecdsa/utils/UpgradeableProxyLib.sol";

/**
 * @title POAStakeRegistryTest
 * @author Lay3r Labs
 * @notice Comprehensive unit tests for the POAStakeRegistry contract
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

    // Signing key private keys and addresses
    uint256 public signingKey1PrivateKey;
    uint256 public signingKey2PrivateKey;
    uint256 public signingKey3PrivateKey;
    address public signingKey1;
    address public signingKey2;
    address public signingKey3;

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
    event OperatorWeightUpdated(address indexed operator, uint256 oldWeight, uint256 newWeight);
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);
    event ThresholdWeightUpdated(uint256 thresholdWeight);
    event QuorumThresholdUpdated(uint256 indexed numerator, uint256 indexed denominator);
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        address indexed newSigningKey,
        address oldSigningKey
    );
    event ServiceURIUpdated(string serviceuri);

    function setUp() public {
        // Create test accounts
        owner = makeAddr("owner");
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        operator3 = makeAddr("operator3");
        nonOperator = makeAddr("nonOperator");

        // Generate signing key private keys and derive addresses
        // Use vm.createWallet to generate address/privateKey pairs dynamically
        Vm.Wallet memory wallet1 = vm.createWallet("signingKey1");
        Vm.Wallet memory wallet2 = vm.createWallet("signingKey2");
        Vm.Wallet memory wallet3 = vm.createWallet("signingKey3");
        signingKey1 = wallet1.addr;
        signingKey1PrivateKey = wallet1.privateKey;
        signingKey2 = wallet2.addr;
        signingKey2PrivateKey = wallet2.privateKey;
        signingKey3 = wallet3.addr;
        signingKey3PrivateKey = wallet3.privateKey;

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
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidAddressZero.selector));
        UpgradeableProxyLib.upgradeAndCall(
            poaStakeRegistryProxy, poaStakeRegistryImpl, poaStakeRegistryInvalidUpgradeCall
        );

        bytes memory poaStakeRegistryUpgradeCall = abi.encodeCall(
            POAStakeRegistry.initialize,
            (owner, INITIAL_THRESHOLD_WEIGHT, INITIAL_QUORUM_NUMERATOR, INITIAL_QUORUM_DENOMINATOR)
        );
        UpgradeableProxyLib.upgradeAndCall(
            poaStakeRegistryProxy, poaStakeRegistryImpl, poaStakeRegistryUpgradeCall
        );
        poaStakeRegistry = POAStakeRegistry(poaStakeRegistryProxy);
        vm.stopPrank();
    }

    // Test initialization
    function test_Initialization() public view {
        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), INITIAL_THRESHOLD_WEIGHT);
        (uint256 numerator, uint256 denominator) = poaStakeRegistry.getLastCheckpointQuorum();
        assertEq(numerator, INITIAL_QUORUM_NUMERATOR);
        assertEq(denominator, INITIAL_QUORUM_DENOMINATOR);
        assertEq(poaStakeRegistry.owner(), owner);
    }

    // Test operator registration
    function test_RegisterOperator() public {
        vm.startPrank(owner);

        vm.expectEmit(true, false, false, true);
        emit OperatorRegistered(operator1);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        assertTrue(poaStakeRegistry.operatorRegistered(operator1));
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), OPERATOR_WEIGHT_1);
        assertEq(poaStakeRegistry.getLastCheckpointTotalWeight(), OPERATOR_WEIGHT_1);

        vm.stopPrank();
    }

    function test_RegisterOperator_InvalidWeight() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidWeight.selector));
        poaStakeRegistry.registerOperator(operator1, 0);
        vm.stopPrank();
    }

    function test_RegisterOperator_AlreadyRegistered() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);

        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.OperatorAlreadyRegistered.selector)
        );
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_2);

        vm.stopPrank();
    }

    function test_RegisterOperator_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
    }

    // Test operator deregistration
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
            abi.encodeWithSelector(IPOAStakeRegistryErrors.OperatorNotRegistered.selector)
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

    // Test weight updates
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

        // Should not revert, just set weight to 0
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_1);
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), 0);

        vm.stopPrank();
    }

    // Test threshold weight updates
    function test_UpdateStakeThreshold() public {
        vm.startPrank(owner);

        uint256 newThreshold = INITIAL_THRESHOLD_WEIGHT + 500;

        vm.expectEmit(false, false, false, true);
        emit ThresholdWeightUpdated(newThreshold);

        poaStakeRegistry.updateStakeThreshold(newThreshold);

        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), newThreshold);

        vm.stopPrank();
    }

    function test_UpdateStakeThreshold_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.updateStakeThreshold(1500);
    }

    // Test quorum updates
    function test_UpdateQuorum() public {
        vm.startPrank(owner);

        uint256 newNumerator = 3;
        uint256 newDenominator = 4;

        vm.expectEmit(false, false, false, true);
        emit QuorumThresholdUpdated(newNumerator, newDenominator);

        poaStakeRegistry.updateQuorum(newNumerator, newDenominator);

        (uint256 numerator, uint256 denominator) = poaStakeRegistry.getLastCheckpointQuorum();
        assertEq(numerator, newNumerator);
        assertEq(denominator, newDenominator);

        vm.stopPrank();
    }

    function test_UpdateQuorum_InvalidQuorum() public {
        vm.startPrank(owner);

        // Test with zero denominator
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidQuorum.selector));
        poaStakeRegistry.updateQuorum(1, 0);

        // Test with numerator > denominator
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidQuorum.selector));
        poaStakeRegistry.updateQuorum(5, 3);

        vm.stopPrank();
    }

    function test_UpdateQuorum_OnlyOwner() public {
        vm.prank(nonOperator);
        vm.expectRevert();
        poaStakeRegistry.updateQuorum(3, 4);
    }

    // Test signing key updates
    function test_UpdateOperatorSigningKey() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);

        vm.expectEmit(true, true, true, true);
        emit SigningKeyUpdate(operator1, block.number, signingKey1, address(0));

        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);

        assertEq(poaStakeRegistry.getLatestOperatorSigningKey(operator1), signingKey1);

        vm.stopPrank();
    }

    function test_UpdateOperatorSigningKey_NotRegistered() public {
        vm.prank(operator1);
        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.OperatorNotRegistered.selector)
        );

        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
    }

    function test_UpdateOperatorSigningKey_OnlyOperator() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.prank(nonOperator);
        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.OperatorNotRegistered.selector)
        );

        _updateOperatorSigningKey(nonOperator, signingKey1, signingKey1PrivateKey);
    }

    function test_UpdateOperatorSigningKey_SameKey() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);

        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);

        // Should not emit event for same key
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);

        assertEq(poaStakeRegistry.getLatestOperatorSigningKey(operator1), signingKey1);

        vm.stopPrank();
    }

    // Test service URI management
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

    // Test WAVS Service Manager interface functions
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
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        assertEq(poaStakeRegistry.getLatestOperatorForSigningKey(signingKey1), operator1);
    }

    // Test view functions
    function test_GetOperatorSigningKeyAtBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        _advanceBlocks(10);
        _updateOperatorSigningKey(operator1, signingKey2, signingKey2PrivateKey);
        vm.stopPrank();

        // Test current state
        assertEq(poaStakeRegistry.getLatestOperatorSigningKey(operator1), signingKey2);

        // Test historical data
        assertEq(
            poaStakeRegistry.getOperatorSigningKeyAtBlock(operator1, uint32(block.number - 1)),
            signingKey1
        );
    }

    function test_GetOperatorWeightAtBlock() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        _advanceBlocks(10);
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        // Test current state
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), OPERATOR_WEIGHT_2);

        // Test historical data
        assertEq(
            poaStakeRegistry.getOperatorWeightAtBlock(operator1, uint32(block.number - 1)),
            OPERATOR_WEIGHT_1
        );
    }

    function test_GetTotalWeightAtBlock() public {
        vm.startPrank(owner);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        _advanceBlocks(10);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        // Test current state
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(), OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2
        );

        // Test historical data
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeightAtBlock(uint32(block.number - 1)),
            OPERATOR_WEIGHT_1
        );
    }

    function test_GetThresholdWeightAtBlock() public {
        vm.startPrank(owner);

        _advanceBlocks(10);
        poaStakeRegistry.updateStakeThreshold(1500);
        vm.stopPrank();

        // Test current state
        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), 1500);

        // Test historical data
        assertEq(
            poaStakeRegistry.getLastCheckpointThresholdWeightAtBlock(uint32(block.number - 1)),
            INITIAL_THRESHOLD_WEIGHT
        );
    }

    function test_GetQuorumAtBlock() public {
        vm.startPrank(owner);

        _advanceBlocks(10);
        poaStakeRegistry.updateQuorum(3, 4);
        vm.stopPrank();

        // Test current state
        (uint256 num, uint256 den) = poaStakeRegistry.getLastCheckpointQuorum();
        assertEq(num, 3);
        assertEq(den, 4);

        // Test historical data
        (uint256 histNum, uint256 histDen) =
            poaStakeRegistry.getLastCheckpointQuorumAtBlock(uint32(block.number - 1));
        assertEq(histNum, INITIAL_QUORUM_NUMERATOR);
        assertEq(histDen, INITIAL_QUORUM_DENOMINATOR);
    }

    // Test signature validation with real ECDSA signatures
    function test_IsValidSignature_ValidSignatures() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        vm.startPrank(operator2);
        _updateOperatorSigningKey(operator2, signingKey2, signingKey2PrivateKey);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](2);
        signers[0] = signingKey2;
        signers[1] = signingKey1;

        // Create valid signatures using vm.sign
        bytes[] memory signatures = new bytes[](2);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signingKey2PrivateKey, digest);
        signatures[0] = abi.encodePacked(r1, s1, v1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signingKey1PrivateKey, digest);
        signatures[1] = abi.encodePacked(r2, s2, v2);

        _advanceBlocks(1);
        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        // This should now pass with valid signatures
        bytes4 result = poaStakeRegistry.isValidSignature(digest, signatureData);
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function test_IsValidSignature_LengthMismatch() public {
        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](2);
        signers[0] = signingKey1;
        signers[1] = signingKey2;

        bytes[] memory signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r, s, v);

        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.LengthMismatch.selector));
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InvalidLength() public {
        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](0);
        bytes[] memory signatures = new bytes[](0);

        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidLength.selector));
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InvalidReferenceBlock() public {
        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](1);
        signers[0] = signingKey1;

        bytes[] memory signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r, s, v);

        // Use current block number (should be invalid)
        bytes memory signatureData = _createSignatureData(signers, signatures, uint32(block.number));

        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidReferenceBlock.selector)
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_NotSorted() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](2);
        signers[0] = signingKey1;
        signers[1] = signingKey2;

        bytes[] memory signatures = new bytes[](2);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r1, s1, v1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signingKey2PrivateKey, digest);
        signatures[1] = abi.encodePacked(r2, s2, v2);

        // Update signing keys
        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        vm.startPrank(operator2);
        _updateOperatorSigningKey(operator2, signingKey2, signingKey2PrivateKey);
        vm.stopPrank();

        _advanceBlocks(1);
        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.NotSorted.selector));
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InsufficientSignedStake() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, 100); // Low weight
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](1);
        signers[0] = signingKey1;

        bytes[] memory signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r, s, v);

        _advanceBlocks(1);
        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.InsufficientSignedStake.selector)
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    function test_IsValidSignature_InsufficientQuorum() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        // Set a high quorum requirement
        poaStakeRegistry.updateQuorum(9, 10); // 90% quorum
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        bytes32 digest = keccak256("test message");
        address[] memory signers = new address[](1);
        signers[0] = signingKey1;

        bytes[] memory signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r, s, v);

        _advanceBlocks(1);
        bytes memory signatureData =
            _createSignatureData(signers, signatures, uint32(block.number - 1));

        vm.expectRevert(
            abi.encodeWithSelector(IWavsServiceManager.InsufficientQuorum.selector, 1000, 9, 3000)
        );
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    // Test WAVS Service Handler integration
    function test_Validate_ValidEnvelope() public {
        vm.startPrank(owner);
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        IWavsServiceHandler.Envelope memory envelope = IWavsServiceHandler.Envelope({
            eventId: bytes20(uint160(1)),
            ordering: bytes12(0),
            payload: "test123"
        });

        bytes32 messageHash = keccak256(abi.encode(envelope));
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        address[] memory signers = new address[](1);
        signers[0] = signingKey1;

        bytes[] memory signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey1PrivateKey, digest);
        signatures[0] = abi.encodePacked(r, s, v);

        _advanceBlocks(1);
        IWavsServiceHandler.SignatureData memory signatureData = IWavsServiceHandler.SignatureData({
            signers: signers,
            signatures: signatures,
            referenceBlock: uint32(block.number - 1)
        });

        // This should not revert
        poaStakeRegistry.validate(envelope, signatureData);
    }

    function test_MultipleOperators_WeightCalculation() public {
        vm.startPrank(owner);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        assertEq(poaStakeRegistry.getLastCheckpointTotalWeight(), OPERATOR_WEIGHT_1);

        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(), OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2
        );

        poaStakeRegistry.registerOperator(operator3, OPERATOR_WEIGHT_3);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + OPERATOR_WEIGHT_3
        );

        poaStakeRegistry.deregisterOperator(operator2);
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeight(), OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_3
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

        // Verify current state consistency
        uint256 actualTotalWeight = poaStakeRegistry.getLastCheckpointTotalWeight();
        assertEq(actualTotalWeight, OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + 500);

        // Verify individual operator weights are correct
        assertEq(poaStakeRegistry.getOperatorWeight(operator1), OPERATOR_WEIGHT_1 + 500);
        assertEq(poaStakeRegistry.getOperatorWeight(operator2), OPERATOR_WEIGHT_2);

        // Test historical data
        assertEq(
            poaStakeRegistry.getLastCheckpointTotalWeightAtBlock(uint32(block.number - 1)),
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + 500
        );
    }

    function test_ReturnSelector() public {
        bytes32 digest = keccak256("test");
        bytes memory signatureData = abi.encode(new address[](0), new bytes[](0), uint32(0));

        // This will revert due to invalid length, but we can test the return value structure
        vm.expectRevert();
        poaStakeRegistry.isValidSignature(digest, signatureData);
    }

    // Test gas optimization scenarios
    function test_GasOptimization_MultipleUpdates() public {
        vm.startPrank(owner);

        // Register multiple operators in one transaction
        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);
        poaStakeRegistry.registerOperator(operator3, OPERATOR_WEIGHT_3);

        // Update weights
        poaStakeRegistry.updateOperatorWeight(operator1, OPERATOR_WEIGHT_1 + 100);
        poaStakeRegistry.updateOperatorWeight(operator2, OPERATOR_WEIGHT_2 + 200);

        // Update threshold and quorum
        poaStakeRegistry.updateStakeThreshold(2000);
        poaStakeRegistry.updateQuorum(3, 4);

        vm.stopPrank();

        // Verify final state
        uint256 expectedWeight =
            OPERATOR_WEIGHT_1 + OPERATOR_WEIGHT_2 + OPERATOR_WEIGHT_3 + 100 + 200;
        assertEq(poaStakeRegistry.getLastCheckpointTotalWeight(), expectedWeight);
        assertEq(poaStakeRegistry.getLastCheckpointThresholdWeight(), 2000);
        (uint256 num, uint256 den) = poaStakeRegistry.getLastCheckpointQuorum();
        assertEq(num, 3);
        assertEq(den, 4);
    }

    function test_InputParametersInvalid() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidThresholdWeight.selector)
        );
        poaStakeRegistry.updateStakeThreshold(0);

        poaStakeRegistry.registerOperator(operator1, OPERATOR_WEIGHT_1);
        poaStakeRegistry.registerOperator(operator2, OPERATOR_WEIGHT_2);

        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidAddressZero.selector));
        poaStakeRegistry.deregisterOperator(address(0));

        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidAddressZero.selector));
        poaStakeRegistry.registerOperator(address(0), OPERATOR_WEIGHT_1);
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidWeight.selector));
        poaStakeRegistry.updateOperatorWeight(operator1, uint256(type(uint160).max) + 1);
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidAddressZero.selector));
        poaStakeRegistry.updateOperatorWeight(address(0), OPERATOR_WEIGHT_1);
        vm.stopPrank();

        vm.startPrank(operator1);
        _updateOperatorSigningKey(operator1, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();

        vm.startPrank(operator2);
        vm.expectRevert(abi.encodeWithSelector(IPOAStakeRegistryErrors.InvalidAddressZero.selector));
        _updateOperatorSigningKey(operator2, address(0), signingKey2PrivateKey);
        vm.expectRevert(abi.encodeWithSelector(IWavsServiceManager.InvalidSignature.selector));
        _updateOperatorSigningKey(operator2, signingKey2, signingKey1PrivateKey);
        vm.expectRevert(
            abi.encodeWithSelector(IPOAStakeRegistryErrors.SigningKeyAlreadyAssigned.selector)
        );
        _updateOperatorSigningKey(operator2, signingKey1, signingKey1PrivateKey);
        vm.stopPrank();
    }

    // Helper functions
    function _generateSignature(
        address signer,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        // This is a mock signature for testing purposes
        // In real tests, you would use actual ECDSA signatures
        return abi.encodePacked(signer, digest);
    }

    /**
     * @notice Update operator signing key with proper signature
     * @param operator The operator address
     * @param signingKey The signing key address
     * @param signingKeyPrivateKey The private key of the signing key
     */
    function _updateOperatorSigningKey(
        address operator,
        address signingKey,
        uint256 signingKeyPrivateKey
    ) internal {
        // Generate the message hash that needs to be signed
        bytes32 messageHash = keccak256(abi.encode(operator));

        // Generate the signature using the signing key's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKeyPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Update the signing key
        poaStakeRegistry.updateOperatorSigningKey(signingKey, signature);
    }

    function _createSignatureData(
        address[] memory signers,
        bytes[] memory signatures,
        uint32 referenceBlock
    ) internal pure returns (bytes memory) {
        return abi.encode(signers, signatures, referenceBlock);
    }

    function _advanceBlocks(
        uint256 blocks
    ) internal {
        vm.roll(block.number + blocks);
    }
}
