// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { MerkleProofUpgradeable } from "./MerkleProofUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

contract MerkleTokenDistributor is Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Epoch {
        bytes32 root;
        address token;
        uint256 supply;
        mapping(bytes32 => bool) claimeds;
    }

    address public owner;
    uint256 public total;

    mapping(uint256 => Epoch) private epochs;

    event NewRoot(bytes32 _root, address _token, uint256 _supply);
    event Claimed(uint256 _epoch, address _recipient, address _token, uint256 _amounts);
    event SetOwner(address _owner);
    event AddToken(uint256 _epoch, uint256 _amounts, uint256 _supply);

    modifier onlyOwner() {
        require(owner == msg.sender, "MerkleTokenDistributor: Caller is not the owner");
        _;
    }

    function setOwner(address _owner) public onlyOwner {
        require(_owner != address(0), "MerkleTokenDistributor: Empty owner");

        owner = _owner;

        emit SetOwner(_owner);
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _owner) external initializer {
        __ReentrancyGuard_init();

        owner = _owner;
    }

    function newRootFromAdmin(bytes32 _root, address _token, uint256 _supply) public onlyOwner {
        require(_root != bytes32(0), "MerkleTokenDistributor: Empty root");
        require(_token != address(0), "MerkleTokenDistributor: Empty token");
        require(_supply > 0, "MerkleTokenDistributor: Empty supply");

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _supply);

        Epoch storage root = epochs[++total];

        root.root = _root;
        root.token = _token;
        root.supply = _supply;

        emit NewRoot(_root, _token, _supply);
    }

    function newRootFromBalance(bytes32 _root, address _token, uint256 _supply) public onlyOwner {
        require(_root != bytes32(0), "MerkleTokenDistributor: Empty root");
        require(_token != address(0), "MerkleTokenDistributor: Empty token");
        require(_supply > 0, "MerkleTokenDistributor: Empty supply");
        require(_balanceOf(_token, address(this)) >= _supply, "MerkleTokenDistributor: Insufficient _token balance");

        Epoch storage root = epochs[++total];

        root.root = _root;
        root.token = _token;
        root.supply = _supply;

        emit NewRoot(_root, _token, _supply);
    }

    function addToken(uint256 _epoch, uint256 _amounts) public onlyOwner {
        require(_amounts > 0, "MerkleTokenDistributor: Empty amounts");

        Epoch storage epoch = epochs[_epoch];

        IERC20Upgradeable(epoch.token).safeTransferFrom(msg.sender, address(this), _amounts);

        epoch.supply = epoch.supply + _amounts;

        emit AddToken(_epoch, _amounts, epoch.supply);
    }

    function getEpoch(uint256 _epoch) public view returns (bytes32, address, uint256) {
        Epoch storage epoch = epochs[_epoch];

        return (epoch.root, epoch.token, epoch.supply);
    }

    function isClaimed(uint256 _epoch, address _recipient, uint256 _amounts) public view returns (bool) {
        Epoch storage epoch = epochs[_epoch];

        return epoch.claimeds[_encodePacked(_recipient, _amounts)];
    }

    function claim(uint256 _epoch, address _recipient, uint256 _amounts, bytes32[] calldata _proof) external nonReentrant {
        Epoch storage epoch = epochs[_epoch];
        bytes32 leaf = _encodePacked(_recipient, _amounts);

        require(_verify(epoch.root, leaf, _proof), "MerkleTokenDistributor: Invalid merkle proof");
        require(!isClaimed(_epoch, _recipient, _amounts), "MerkleTokenDistributor: Already claimed");
        require(epoch.supply >= _amounts, "MerkleTokenDistributor: Insufficient amounts");

        IERC20Upgradeable(epoch.token).safeTransfer(_recipient, _amounts);

        epoch.supply = epoch.supply - _amounts;
        epoch.claimeds[leaf] = true;

        emit Claimed(_epoch, _recipient, epoch.token, _amounts);
    }

    function _encodePacked(address _recipient, uint256 _amounts) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_recipient, _amounts));
    }

    function _verify(bytes32 _root, bytes32 _leaf, bytes32[] memory _proof) internal pure returns (bool) {
        return MerkleProofUpgradeable.verify(_proof, _root, _leaf);
    }

    function _balanceOf(address _token, address _recipient) internal view returns (uint256) {
        return IERC20Upgradeable(_token).balanceOf(_recipient);
    }
}

