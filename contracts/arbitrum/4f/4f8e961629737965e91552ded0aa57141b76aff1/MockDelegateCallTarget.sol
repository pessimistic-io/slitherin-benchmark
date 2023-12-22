// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract MockDelegateCallTarget {
    // same storage layout as VariablesV1.sol
    address internal _avoWalletImpl;
    uint88 internal _avoSafeNonce;
    uint8 internal _status;
    address internal _owner;
    uint8 internal _initialized;
    bool internal _initializing;
    mapping(bytes32 => uint256) internal _signedMessages;
    mapping(bytes32 => uint256) public nonSequentialNonces;
    uint256[50] private __gap;
    // storage slot 54 (Multisig):
    address internal _signersPointer;
    uint8 internal requiredSigners;
    uint8 internal signersCount;

    // custom storage for mock contract after gap
    uint256[45] private __gap2;

    uint256 public callCount;

    bytes32 public constant TAMPERED_KEY = keccak256("TESTKEY");

    event Called(address indexed sender, bytes data, uint256 indexed usedBalance, uint256 callCount);

    function emitCalled() external payable {
        callCount = callCount + 1;

        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function tryModifyOwner() external {
        callCount = callCount + 1;

        _owner = address(0x01);
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function tryModifyAvoWalletImpl() external {
        callCount = callCount + 1;

        _avoWalletImpl = address(0x01);
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function tryModifyAvoSafeNonce() external {
        callCount = callCount + 1;

        _avoSafeNonce = 42375823785;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetStatus() external {
        callCount = callCount + 1;

        _status = 77;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetInitializing() external {
        callCount = callCount + 1;

        _initializing = true;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetInitialized() external {
        callCount = callCount + 1;

        _initialized = 77;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetSignersPointer() external {
        callCount = callCount + 1;

        _signersPointer = address(1);
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetRequiredSigners() external {
        callCount = callCount + 1;

        requiredSigners = 77;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetSignersCount() external {
        callCount = callCount + 1;

        signersCount = 77;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function trySetSignedMessage() external {
        callCount = callCount + 1;

        _signedMessages[TAMPERED_KEY] = 77;
        emit Called(msg.sender, msg.data, 0, callCount);
    }

    function triggerRevert() external pure {
        revert("MOCK_REVERT");
    }

    function transferAmountTo(address to, uint256 amount) external payable {
        callCount = callCount + 1;

        payable(to).transfer(amount);

        emit Called(msg.sender, msg.data, amount, callCount);
    }
}

