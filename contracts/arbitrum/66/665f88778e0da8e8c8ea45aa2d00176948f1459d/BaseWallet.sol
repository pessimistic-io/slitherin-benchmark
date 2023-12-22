// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

import "./UUPSUpgradeable.sol";
import "./IEntryPoint.sol";
import "./UniversalReceiver.sol";

abstract contract BaseWallet is UUPSUpgradeable, UniversalReceiver {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    event Commit(bytes32 indexed commitment, uint256 indexed creationTime, uint256 indexed timestamp);
    event UserOp(
        bytes32 indexed userOpHash,
        uint256 indexed nonce,
        bytes32 indexed domainSeparator,
        IEntryPoint entryPoint,
        uint256 walletCreationTime,
        bytes32 challenge
    );

    string constant ACCESS_DENIED = "My potions are too strong for you";

    string public constant VERSION = "1.3.3";
    uint256 public constant COMMIT_DURATION = 3.5 days;

    bytes32 public immutable DOMAIN_SEPARATOR;
    uint256 public immutable CREATION_TIME = block.timestamp;
    IEntryPoint public immutable ENTRY_POINT;
    address immutable WALLET = msg.sender;
    address immutable SIGNER;

    uint256 constant N_GUARDIANS = 4;
    uint256 immutable MIN_GUARDIANS;
    address immutable GUARDIAN0;
    address immutable GUARDIAN1;
    address immutable GUARDIAN2;
    address immutable GUARDIAN3;

    mapping (bytes32 => uint256) commitments;
    bytes32 currentUserOpHash;
    bytes32 salt;

    constructor(IEntryPoint entryPoint, address signer, uint256 minGuardians, address guardian0, address guardian1, address guardian2, address guardian3) {
        require(minGuardians <= N_GUARDIANS, "minGuardians is too high");
        ENTRY_POINT = entryPoint;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"),
            keccak256("Moushley"),
            keccak256(bytes(VERSION)),
            block.chainid,
            msg.sender,
            keccak256(abi.encode(entryPoint, CREATION_TIME))
        ));
        SIGNER = signer;
        MIN_GUARDIANS = minGuardians;
        GUARDIAN0 = guardian0;
        GUARDIAN1 = guardian1;
        GUARDIAN2 = guardian2;
        GUARDIAN3 = guardian3;
    }

    function getImplementation() public view returns (address implementation) {
        return _getImplementation();
    }

    function _eip712(bytes32 messageHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            messageHash
        ));
    }

    modifier onlyEntryPoint() {
        require(msg.sender == address(ENTRY_POINT), ACCESS_DENIED);
        _;
    }

    modifier onlyWalletOrEntryPoint() {
        require(msg.sender == address(ENTRY_POINT) || msg.sender == WALLET, ACCESS_DENIED);
        _;
    }

    modifier walletAction() virtual {
        require(msg.sender == address(ENTRY_POINT) || msg.sender == WALLET, ACCESS_DENIED);
        _;
    }

    function setSalt(bytes32 _salt) public onlyWalletOrEntryPoint {
        salt = _salt;
    }

    function _commit(bytes32 commitment, uint256 timestamp) internal {
        commitments[commitment] = timestamp;
        emit Commit(commitment, CREATION_TIME, timestamp);
    }

    function _checkCommitment(bytes32 commitment) internal view returns (bool) {
        return commitments[commitment] >= CREATION_TIME && (commitments[commitment] == CREATION_TIME || commitments[commitment] <= block.timestamp - COMMIT_DURATION);
    }

    function commit(bytes32 commitment) public onlyWalletOrEntryPoint {
        _commit(commitment, block.timestamp);
    }

    function commitWithSignatures(bytes32 commitment, Signature[N_GUARDIANS] calldata signatures) public onlyWalletOrEntryPoint {
        bytes32 challenge = _eip712(keccak256(abi.encode(
            keccak256("CommitWithSignaturesChallenge(bytes32 commitment)"),
            commitment
        )));
        require(
            (GUARDIAN0 == ecrecover(challenge, signatures[0].v, signatures[0].r, signatures[0].s) ? 1 : 0)
                + (GUARDIAN1 == ecrecover(challenge, signatures[1].v, signatures[1].r, signatures[1].s) ? 1 : 0)
                + (GUARDIAN2 == ecrecover(challenge, signatures[2].v, signatures[2].r, signatures[2].s) ? 1 : 0)
                + (GUARDIAN3 == ecrecover(challenge, signatures[3].v, signatures[3].r, signatures[3].s) ? 1 : 0)
                >= MIN_GUARDIANS,
            "Invalid signatures"
        );
        _commit(commitment, CREATION_TIME);
    }

    function _userOpHashChallenge(bytes32 nameHash) internal view returns (bool) {
        bytes32 challenge = _eip712(keccak256(abi.encode(
            keccak256("UserOpHashChallenge(string name,bytes32 salt,bytes32 userOpHash)"),
            nameHash,
            salt,
            currentUserOpHash
        )));
        return _checkCommitment(challenge);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyWalletOrEntryPoint {
        bytes32 challenge = _eip712(keccak256(abi.encode(
            keccak256("UpgradeChallenge(bytes32 salt,address newImplementation)"),
            salt,
            newImplementation
        )));
        require(_checkCommitment(challenge), "You lack patience");
        _commit(challenge, 0);
    }

    function _beforeMultiCall(Call[] calldata calls) internal virtual {}

    function _multiCall(Call[] calldata calls) internal {
        _beforeMultiCall(calls);
        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success,) = payable(calls[i].to).call{value: calls[i].value}(calls[i].data);
            if (!success) {
                assembly ("memory-safe") {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
        }
    }

    function multiCall(Call[] calldata calls) public payable walletAction {
        _multiCall(calls);
    }

    function _deploy(bytes memory _initCode, bytes32 _salt) internal returns (address) {
        address deployed;
        assembly ("memory-safe") {
            deployed := create2(0, add(_initCode, 0x20), mload(_initCode), _salt)
        }
        require(deployed != address(0), "CREATE2 failed");
        return deployed;
    }

    function deploy(bytes calldata _initCode, bytes32 _salt) public walletAction {
        _deploy(_initCode, _salt);
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public onlyEntryPoint returns (uint256 validationData) {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            require(success, "Insufficient funds");
        }

        bytes32 challenge = _eip712(keccak256(abi.encode(
            keccak256("UserOpChallenge(bytes32 userOpHash)"),
            userOpHash
        )));
        currentUserOpHash = userOpHash;
        emit UserOp(userOpHash, userOp.nonce, DOMAIN_SEPARATOR, ENTRY_POINT, CREATION_TIME, challenge);

        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes calldata signature = userOp.signature;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := and(calldataload(add(signature.offset, 0x21)), 0xff)
        }
        return ecrecover(challenge, v, r, s) != SIGNER ? 1 : 0;
    }
}

