// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Pausable} from "./Pausable.sol";
import {IERC20} from "./IERC20.sol";

import {IMAHAXLocker} from "./IMAHAXLocker.sol";
import {MerkleWhitelist} from "./MerkleWhitelist.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";

contract MAHAXMint is Pausable, MerkleWhitelist, VersionedInitializable {
    uint256 public startTime;
    IERC20 public maha;
    IMAHAXLocker public locker;

    mapping(address => bool) public minted;
    uint256 public mintCount;
    bool public disableWhitelist;

    function initialize(
        IERC20 _maha,
        IMAHAXLocker _locker,
        uint256 _startTime,
        bytes32 root,
        address governance
    ) external initializer {
        // set maha and locker address
        maha = IERC20(_maha);
        locker = IMAHAXLocker(_locker);

        // set start time
        startTime = _startTime;

        // approve locker for maha
        maha.approve(address(locker), type(uint256).max);

        // register merkle proof
        merkleRoot = root;

        _transferOwnership(governance);
    }

    function mint(bytes32[] memory proof) external {
        // checks
        if (!disableWhitelist)
            require(isWhitelisted(msg.sender, proof), "!whitelist");
        require(canStart(), "!started");
        require(!hasMinted(msg.sender), "minted");
        require(tx.origin == msg.sender, "!contract");
        require(availableSpots() > 0, "mint over");

        // effects
        minted[msg.sender] = true;

        // create lock for the minter
        locker.createLockFor(
            100 * 1e18, // uint256 _value,
            86400 * 365 * 4, // uint256 _lockDuration,
            msg.sender, // address _to,
            false // bool _stakeNFT
        );

        // increase mint count; used in frontend
        mintCount++;
    }

    function togglePause() external onlyOwner {
        if (!paused()) _pause();
        else _unpause();
    }

    function toggleWhitelist() external onlyOwner {
        disableWhitelist = !disableWhitelist;
    }

    function hasMinted(address who) public view returns (bool) {
        return minted[who];
    }

    function isOpenForAll() public view returns (bool) {
        return disableWhitelist;
    }

    function canStart() public view returns (bool) {
        return block.timestamp > startTime;
    }

    function availableSpots() public view returns (uint256) {
        return (maha.balanceOf(address(this)) / 100) / 1e18;
    }

    function updateTimestsamp(uint256 _timestamp) external onlyOwner {
        startTime = _timestamp;
    }

    function refund(IERC20 token) external onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function getRevision() public pure virtual override returns (uint256) {
        return 0;
    }
}

