// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IWeb3Registry.sol";
import "./IAddressSetter.sol";
import "./LibWeb3Domain.sol";
import "./LibTransferHelper.sol";
import "./LibURI.sol";
import "./Web3RegistrarVerifier.sol";
import "./Web3ReverseRegistrar.sol";

contract Web3SideRegistrar is Web3RegistrarVerifier {
    using LibTransferHelper for address;
    using SafeERC20 for IERC20;

    IWeb3Registry public registry;
    Web3ReverseRegistrar public reverseRegistrar;
    uint256 public maxSignInterval;
    bytes32 public baseNode;
    address public defaultResolver;
    mapping(bytes32 => bool) private registeredNodes;

    event NameRegistered(string name, address indexed owner);
    event Withdraw(address receiver, uint256 amount);

    function __Web3SideRegistrar_init(
        IWeb3Registry _registry,
        Web3ReverseRegistrar _reverseRegistrar,
        bytes32 _baseNode,
        uint256 _maxSignInterval,
        address verifierAddress
    ) external initializer {
        __Web3SideRegistrar_init_unchained(_registry, _reverseRegistrar, _baseNode, _maxSignInterval, verifierAddress);
    }

    function __Web3SideRegistrar_init_unchained(
        IWeb3Registry _registry,
        Web3ReverseRegistrar _reverseRegistrar,
        bytes32 _baseNode,
        uint256 _maxSignInterval,
        address verifierAddress
    ) internal onlyInitializing {
        __Web3RegistrarVerifier_init_unchained(verifierAddress);
        registry = _registry;
        reverseRegistrar = _reverseRegistrar;
        baseNode = _baseNode;
        maxSignInterval = _maxSignInterval;
    }

    function setResolver(address resolver) external onlyOwner {
        registry.setResolver(baseNode, resolver);
    }

    function setDefaultResolver(address resolver) public onlyOwner {
        require(address(resolver) != address(0), "Resolver address must not be 0");
        defaultResolver = resolver;
    }

    function setMaxSignInterval(uint256 _maxSignInterval) external onlyOwner {
        maxSignInterval = _maxSignInterval;
    }

    function setBaseNode(bytes32 _baseNode) external onlyOwner {
        baseNode = _baseNode;
    }

    function register(LibWeb3Domain.SimpleOrder calldata order, bytes calldata signature) external payable {
        require(order.owner == msg.sender, "not authorized");
        require(order.timestamp <= block.timestamp, "register too early");
        require(order.timestamp + maxSignInterval > block.timestamp, "register too late");
        verifyOrder(order, signature);
        bytes32 node = keccak256(_toLowerStringBytes(order.name)); // lower case
        require(!registeredNodes[node], "name already registered");
        registeredNodes[node] = true;

        _setSubnodeOwnerAndAddr(node, order.owner, order.owner);

        uint256 remain = msg.value - order.price;
        if (remain > 0) {
            msg.sender.transferETH(remain);
        }

        emit NameRegistered(order.name, order.owner);
    }

    // the owner of ethereum may set other chain's owner address
    // the server will sign the request so that the owner of ethereum can reclaim the name on other chain
    function reclaim(LibWeb3Domain.ReclaimNodeRequest calldata request, bytes calldata signature) external {
        _verifyReclaim(request, signature);
        registry.setSubnodeOwner(baseNode, request.node, request.owner);
    }

    function reclaimAndSetAddr(
        LibWeb3Domain.ReclaimNodeRequest calldata request,
        bytes calldata signature,
        address addr
    ) external {
        _verifyReclaim(request, signature);
        _setSubnodeOwnerAndAddr(request.node, request.owner, addr);
    }

    function _verifyReclaim(LibWeb3Domain.ReclaimNodeRequest calldata request, bytes calldata signature) internal view {
        require(request.owner == msg.sender, "not authorized");
        require(request.timestamp <= block.timestamp, "reclaim too early");
        require(request.timestamp + maxSignInterval > block.timestamp, "reclaim too late");
        verifyReclaim(request, signature);
    }

    function _toLowerStringBytes(string calldata str) private pure returns (bytes memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; ++i) {
            // upper case to lower case
            uint8 charCode = uint8(bStr[i]);
            if (charCode >= 65 && charCode <= 90) {
                bLower[i] = bytes1(charCode + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return bLower;
    }

    function _setSubnodeOwnerAndAddr(bytes32 label, address owner, address addr) internal {
        // set owner to this address
        bytes32 node = registry.setSubnodeOwner(baseNode, label, address(this));
        // set resolver and addr
        registry.setResolver(node, defaultResolver);
        IAddressSetter(defaultResolver).setAddr(node, addr);
        // transfer owner
        registry.setOwner(node, owner);
    }

    function withdrawETH(address receiver) external onlyOwner {
        uint256 amount = address(this).balance;
        receiver.transferETH(amount);
        emit Withdraw(receiver, amount);
    }

    function withdrawERC20(IERC20 token, address receiver) external onlyOwner {
        uint256 amount = token.balanceOf(address(this));
        if (amount > 0) {
            token.safeTransfer(receiver, amount);
        }
    }

    uint256[45] private __gap;
}

