// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Address } from "./Address.sol";
import { Ownable } from "./Ownable.sol";

import { ITokenRelease } from "./ITokenRelease.sol";

contract TokenRelease is ReentrancyGuard, ITokenRelease, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 private constant PRECISION = 1e18;

    address public wrappedToken;
    address public operator;

    uint256 public duration;
    uint256 public totalUnclaimedSupply;

    struct ReleaseInfo {
        uint256 total;
        uint256 claimed;
        uint256 blk;
        uint256 startTime;
        uint256 duration;
    }

    mapping(address => ReleaseInfo[]) private releases;

    modifier onlyOperator() {
        require(operator == msg.sender, "TokenRelease: Caller is not operator");
        _;
    }

    constructor(address _wrappedToken) {
        wrappedToken = _wrappedToken;
        duration = 4 weeks;
    }

    function setOperator(address _operator) public onlyOwner {
        operator = _operator;
    }

    function addFund(address _recipient, uint256 _amountIn) public override onlyOperator nonReentrant {
        IERC20(wrappedToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        releases[_recipient].push(ReleaseInfo({ total: _amountIn, claimed: 0, blk: block.number, startTime: block.timestamp, duration: duration }));

        totalUnclaimedSupply += _amountIn;
    }

    function claim() public nonReentrant returns (uint256 total) {
        total = _claim(msg.sender);

        if (total > 0) {
            IERC20(wrappedToken).safeTransfer(msg.sender, total);

            totalUnclaimedSupply -= total;
        }
    }

    function _claim(address _recipient) internal returns (uint256 total) {
        uint256 totalSize = releases[_recipient].length;
        bool[] memory indexes = new bool[](totalSize);

        for (uint256 i = 0; i < totalSize; i++) {
            (, uint256 claimed, bool removed) = _checkpoint(_recipient, i);

            releases[_recipient][i].claimed = releases[_recipient][i].claimed + claimed;
            total += claimed;

            if (removed) {
                indexes[i] = true;
            }
        }
        for (uint256 i = 0; i < totalSize; i++) {
            if (indexes[i]) {
                releases[_recipient][i] = releases[_recipient][releases[_recipient].length - 1];
                releases[_recipient].pop();
            }
        }
    }

    function pendingTokens(address _recipient) public view returns (uint256 total) {
        for (uint256 i = 0; i < releases[_recipient].length; i++) {
            (, uint256 claimed, ) = _checkpoint(_recipient, i);

            total += claimed;
        }
    }

    function lockedOf(address _recipient) external view returns (uint256 total) {
        for (uint256 i = 0; i < releases[_recipient].length; i++) {
            ReleaseInfo storage userRelease = releases[_recipient][i];
            (uint256 t, uint256 claimed, ) = _checkpoint(_recipient, i);

            total += t - userRelease.claimed - claimed;
        }
    }

    function _checkpoint(address _recipient, uint256 _index) public view returns (uint256, uint256, bool) {
        ReleaseInfo storage userRelease = releases[_recipient][_index];

        bool removed;
        uint256 remaining = (userRelease.total / userRelease.duration) * (block.timestamp - userRelease.startTime);

        if (remaining > userRelease.total) {
            remaining = userRelease.total;
        }

        uint256 claimed = remaining - userRelease.claimed;

        if (claimed + userRelease.claimed == userRelease.total) {
            removed = true;
        }

        return (userRelease.total, claimed, removed);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function releasesLength(address _recipient) public view returns (uint256) {
        return releases[_recipient].length;
    }

    function getRelease(address _recipient, uint256 _index) public view returns (ReleaseInfo memory) {
        return releases[_recipient][_index];
    }
}

