// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable2Step.sol";

import "./XDCAToken.sol";
import "./IFeeCollector.sol";
import "./CollectFees.sol";

contract XDCAManager is CollectFees {
    uint256 private constant precision = 1e6;

    uint256 public nextUnbondingId;
    address public dcaToken;
    address public xdcaToken;
    uint256 public maxUnbondingsAmountPerUser;
    uint256 public minimalUnbondingDurationInDays;
    uint256 public maximalUnbondingDurationInDays;
    uint256 public minimalPercentageRatio; // 10000 = 1%
    uint256 public maximalPercentageRatio; // 10000 = 1%

    struct Unbonding {
        uint256 unbondingId;
        uint256 dcaToWithdraw;
        uint256 xdcaToBurn;
        uint256 endTimestamp;
    }

    mapping(address => Unbonding[]) public unbondings;

    event SetDCATokenAddress(address newDCAToken);
    event SetXDCATokenAddress(address newXDCAToken);
    event SetFeeCollector(address newFeeCollector);
    event SetMinimalUnbondingDurationInDays(
        uint256 newMinimalUnbondingDurationInDays
    );
    event SetMaximalUnbondingDurationInDays(
        uint256 newMaximalUnbondingDurationInDays
    );
    event SetMinimalPercentageRatio(uint256 newMinimalPercentageRatio);
    event SetMaximalPercentageRatio(uint256 newMaximalPercentageRatio);
    event SetMaxUnbondingsAmountPerUser(uint256 newMaxUnbondingsAmountPerUser);
    event EmergencyWithdraw(IERC20 tokenToWithdraw, uint256 amountToWithdraw);
    event Lock(address indexed user, uint256 dcaAmount);
    event Unbond(
        uint256 indexed unbondingId,
        address indexed user,
        uint256 xdcaAmount,
        uint256 durationInDays
    );
    event CancelUnbonding(uint256 indexed unbondingId, address indexed user);
    event Unlock(
        uint256 indexed unbondingId,
        address indexed user,
        uint256 withdrawedDCA,
        uint256 burnedXDCA
    );

    constructor(
        address dcaToken_,
        address xdcaToken_,
        address feeCollectorAddress_,
        address feeOracleAddress_,
        uint256 maxUnbondingsAmountPerUser_,
        uint256 minimalUnbondingDurationInDays_,
        uint256 maximalUnbondingDurationInDays_,
        uint256 minimalPercentageRatio_,
        uint256 maximalPercentageRatio_
    ) CollectFees(feeCollectorAddress_, feeOracleAddress_) {
        nextUnbondingId = 1;
        dcaToken = dcaToken_;
        xdcaToken = xdcaToken_;
        maxUnbondingsAmountPerUser = maxUnbondingsAmountPerUser_;
        minimalUnbondingDurationInDays = minimalUnbondingDurationInDays_;
        maximalUnbondingDurationInDays = maximalUnbondingDurationInDays_;
        minimalPercentageRatio = minimalPercentageRatio_;
        maximalPercentageRatio = maximalPercentageRatio_;
    }

    function setDCATokenAddress(address dcaToken_) public onlyOwner {
        dcaToken = dcaToken_;
        emit SetDCATokenAddress(dcaToken_);
    }

    function setXDCATokenAddress(address xdcaToken_) public onlyOwner {
        xdcaToken = xdcaToken_;
        emit SetXDCATokenAddress(xdcaToken_);
    }

    function setMinimalUnbondingDurationInDays(
        uint256 minimalUnbondingDurationInDays_
    ) public onlyOwner {
        minimalUnbondingDurationInDays = minimalUnbondingDurationInDays_;
        emit SetMinimalUnbondingDurationInDays(minimalUnbondingDurationInDays_);
    }

    function setMaximalUnbondingDurationInDays(
        uint256 maximalUnbondingDurationInDays_
    ) public onlyOwner {
        maximalUnbondingDurationInDays = maximalUnbondingDurationInDays_;
        emit SetMaximalUnbondingDurationInDays(maximalUnbondingDurationInDays_);
    }

    function setMinimalPercentageRatio(
        uint256 minimalPercentageRatio_
    ) public onlyOwner {
        minimalPercentageRatio = minimalPercentageRatio_;
        emit SetMinimalPercentageRatio(minimalPercentageRatio_);
    }

    function setMaximalPercentageRatio(
        uint256 maximalPercentageRatio_
    ) public onlyOwner {
        require(
            maximalPercentageRatio_ <= precision,
            "maximalPercentageRatio cannot be greater than 100%"
        );
        maximalPercentageRatio = maximalPercentageRatio_;
        emit SetMaximalPercentageRatio(maximalPercentageRatio_);
    }

    function setMaxUnbondingsAmountPerUser(
        uint256 maxUnbondingsAmountPerUser_
    ) public onlyOwner {
        maxUnbondingsAmountPerUser = maxUnbondingsAmountPerUser_;
        emit SetMaxUnbondingsAmountPerUser(maxUnbondingsAmountPerUser_);
    }

    function emergencyWithdraw(
        IERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) public onlyOwner {
        if (address(tokenToWithdraw) == address(0)) {
            address payable to = payable(msg.sender);
            to.transfer(amountToWithdraw);
        } else {
            tokenToWithdraw.transfer(msg.sender, amountToWithdraw);
        }
        emit EmergencyWithdraw(tokenToWithdraw, amountToWithdraw);
    }

    function getUnbondings(
        address user
    ) public view returns (Unbonding[] memory) {
        return unbondings[user];
    }

    function lock(uint256 dcaAmount) public payable collectFee {
        IERC20(dcaToken).transferFrom(msg.sender, address(this), dcaAmount);
        XDCAToken(xdcaToken).mint(msg.sender, dcaAmount);
        emit Lock(msg.sender, dcaAmount);
    }

    function unbond(
        uint256 xdcaAmount,
        uint256 durationInDays
    ) public payable collectFee {
        require(xdcaAmount > 0, "Amount must be greater than 0");
        require(
            durationInDays >= minimalUnbondingDurationInDays &&
                durationInDays <= maximalUnbondingDurationInDays,
            "Invalid unbonding duration"
        );
        Unbonding[] memory userUnbondings = unbondings[msg.sender];
        require(
            userUnbondings.length < maxUnbondingsAmountPerUser,
            "Max unbondings limit reached"
        );
        unbondings[msg.sender].push(
            Unbonding({
                unbondingId: nextUnbondingId,
                dcaToWithdraw: _calculateDCAToWithdraw(
                    xdcaAmount,
                    durationInDays
                ),
                xdcaToBurn: xdcaAmount,
                endTimestamp: block.timestamp + durationInDays * 24 * 60 * 60
            })
        );
        nextUnbondingId += 1;
        IERC20(xdcaToken).transferFrom(msg.sender, address(this), xdcaAmount);
        emit Unbond(
            nextUnbondingId - 1,
            msg.sender,
            xdcaAmount,
            durationInDays
        );
    }

    function cancelUnbonding(uint256 unbondingId) public payable collectFee {
        (
            Unbonding memory foundUnbonding,
            uint256 foundUnbondingIndex
        ) = _findUnbondingById(msg.sender, unbondingId);
        unbondings[msg.sender][foundUnbondingIndex] = unbondings[msg.sender][
            unbondings[msg.sender].length - 1
        ];
        unbondings[msg.sender].pop();
        IERC20(xdcaToken).transfer(msg.sender, foundUnbonding.xdcaToBurn);
        emit CancelUnbonding(unbondingId, msg.sender);
    }

    function unlock(uint256 unbondingId) public payable collectFee {
        (
            Unbonding memory foundUnbonding,
            uint256 foundUnbondingIndex
        ) = _findUnbondingById(msg.sender, unbondingId);

        require(
            block.timestamp >= foundUnbonding.endTimestamp,
            "Unbonding not finished"
        );
        uint256 dcaToTransfer = foundUnbonding.dcaToWithdraw;
        uint256 xdcaToBurn = foundUnbonding.xdcaToBurn;
        require(dcaToTransfer > 0, "Nothing to unlock");
        unbondings[msg.sender][foundUnbondingIndex] = unbondings[msg.sender][
            unbondings[msg.sender].length - 1
        ];
        unbondings[msg.sender].pop();
        XDCAToken(xdcaToken).burn(xdcaToBurn);
        IERC20(dcaToken).transfer(msg.sender, dcaToTransfer);
        if (xdcaToBurn - dcaToTransfer > 0) {
            IERC20(dcaToken).approve(
                feeCollectorAddress,
                xdcaToBurn - dcaToTransfer
            );
            IFeeCollector(feeCollectorAddress).receiveToken(
                dcaToken,
                xdcaToBurn - dcaToTransfer
            );
        }
        emit Unlock(unbondingId, msg.sender, dcaToTransfer, xdcaToBurn);
    }

    function calculateDCAToWithdraw(
        uint256 amountIn,
        uint256 durationInDays
    ) public view returns (uint256 amountOut) {
        return _calculateDCAToWithdraw(amountIn, durationInDays);
    }

    function _calculateDCAToWithdraw(
        uint256 amountIn,
        uint256 durationInDays
    ) internal view returns (uint256 amountOut) {
        uint256 unbondingDurationFactor = (precision *
            (durationInDays - minimalUnbondingDurationInDays)) /
            (maximalUnbondingDurationInDays - minimalUnbondingDurationInDays);
        return
            (amountIn * minimalPercentageRatio) /
            precision +
            ((amountIn * (maximalPercentageRatio - minimalPercentageRatio)) *
                unbondingDurationFactor) /
            (precision * precision);
    }

    function _findUnbondingById(
        address user,
        uint256 unbondingId
    ) internal view returns (Unbonding memory, uint256) {
        Unbonding[] memory userUnbondings = unbondings[user];
        Unbonding memory foundUnbonding;
        uint256 foundUnbondingIndex;
        for (uint256 i = 0; i < userUnbondings.length; i++) {
            if (userUnbondings[i].unbondingId == unbondingId) {
                foundUnbonding = userUnbondings[i];
                foundUnbondingIndex = i;
                break;
            }
        }
        require(foundUnbonding.xdcaToBurn > 0, "Unbonding not found");
        return (foundUnbonding, foundUnbondingIndex);
    }
}

