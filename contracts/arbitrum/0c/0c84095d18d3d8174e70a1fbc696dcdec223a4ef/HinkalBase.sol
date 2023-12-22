// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Merkle.sol";
import "./IHinkalBase.sol";
import "./IMerkle.sol";
import "./Transferer.sol";
import "./IAccessToken.sol";
import "./IRelayStore.sol";
import "./IWrapper.sol";
import "./IERC20TokenRegistry.sol";
import "./IPoseidon4.sol";

contract HinkalBase is IHinkalBase, Ownable, Transferer, ReentrancyGuard {
    IMerkle public immutable merkleTree;
    IAccessToken public immutable accessToken;
    IERC20TokenRegistry public immutable ERC20TokenRegistry;
    IRelayStore public immutable relayStore;

    IPoseidon4 immutable poseidon4; // hashing

    mapping(uint256 => bool) public nullifiers;

    uint256 constant P =
        21888242871839275222246405745257275088548364400416034343698204186575808495617; // https://docs.circom.io/circom-language/basic-operators/

    constructor(
        address poseidon4Address,
        address merkleTreeAddress,
        address accessTokenAddress,
        address erc20TokenRegistryAddress,
        address relayStoreAddress
    ) {
        poseidon4 = IPoseidon4(poseidon4Address);
        merkleTree = IMerkle(merkleTreeAddress);
        accessToken = IAccessToken(accessTokenAddress);
        ERC20TokenRegistry = IERC20TokenRegistry(erc20TokenRegistryAddress);
        relayStore = IRelayStore(relayStoreAddress);
    }

    modifier checkTokenRegistry(
        address inErc20TokenAddress,
        address outErc20TokenAddress,
        int256 publicAmount
    ) {
        require(
            ERC20TokenRegistry.tokenInRegistry(outErc20TokenAddress),
            "Transaction with this ERC20 Token not allowed."
        );
        uint256 tokenLimit = ERC20TokenRegistry.getTokenLimit(
            inErc20TokenAddress
        );
        if (tokenLimit > 0 && publicAmount != 0) {
            require(
                uint256(publicAmount > 0 ? publicAmount : -publicAmount) <
                    tokenLimit,
                "Transaction Limit Exceeded"
            );
        }
        _;
    }

    receive() external payable {}

    function isNullifierSpent(uint256 nullifierHash)
        public
        view
        returns (bool)
    {
        return nullifiers[nullifierHash];
    }

    function relayPercentage() public view returns (uint8) {
        return relayStore.relayPercentage();
    }

    function relayPercentageSwap() public view returns (uint8) {
        return relayStore.relayPercentageSwap();
    }

    function getRelayList() public view returns (RelayEntry[] memory) {
        return relayStore.getRelayList();
    }

    function register(bytes calldata shieldedAddressHash) external {
        require(
            !accessToken.blacklistAddresses(msg.sender),
            "Blacklisted addresses aren't allowed to register"
        );
        emit Register(msg.sender, shieldedAddressHash);
    }

    function insertCommitment(uint256 commitment, bytes memory encryptedOutput)
        internal
    {
        uint256 index = merkleTree.insert(commitment);
        // Emitting New Commitments in Logs
        emit NewCommitment(commitment, index, encryptedOutput);
    }
}

