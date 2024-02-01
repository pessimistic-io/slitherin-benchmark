//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import "./IERC20.sol";

import "./ISpecialPool.sol";

import "./SpecialValidatePoolLibrary.sol";

library SpecialEndPoolLibrary {

    function cancelPool(
        ISpecialPool.PoolModel storage poolInformation,
        address poolOwner,
        address _pool
    ) external {
        SpecialValidatePoolLibrary._poolIsNotCancelled(poolInformation);
        IERC20 projectToken = IERC20(poolInformation.projectTokenAddress);
        poolInformation.status = ISpecialPool.PoolStatus.Cancelled;
        ISpecialPool(payable(_pool)).sendToken(
            poolInformation.projectTokenAddress,
            projectToken.balanceOf(_pool),
            poolOwner
        );
    }

    function forceCancelPool(ISpecialPool.PoolModel storage poolInformation)
        external
    {
        SpecialValidatePoolLibrary._poolIsNotCancelled(poolInformation);
        poolInformation.status = ISpecialPool.PoolStatus.Cancelled;
    }

    function claimToken(
        ISpecialPool.PoolModel storage poolInformation,
        mapping(address => uint256) storage collaborations,
        mapping(address => uint256) storage unlockedVestingAmount,
        ISpecialPool.UserVesting storage userVesting,
        mapping(address => bool) storage _didRefund,
        address _pool,
        uint256 _cliff,
        uint256 fundRaiseTokenDecimals
    ) external {
        SpecialValidatePoolLibrary._poolIsAllowed(poolInformation);
        uint256 _amount = collaborations[msg.sender]
            *poolInformation.specialSaleRate
            /(10**fundRaiseTokenDecimals);
        if (!userVesting.isVesting) {
            if (_didRefund[msg.sender] != true && _amount > 0) {
                _didRefund[msg.sender] = true;
                ISpecialPool(payable(_pool)).sendToken(
                    poolInformation.projectTokenAddress,
                    _amount,
                    msg.sender
                );
            }
        } else {
            uint256 tokenToBeUnlockPercent = userVesting.firstPercent;
            uint256 tokenToBeUnlock = 0;
            uint256 now_date = poolInformation.endDateTime+(
                _cliff * 1 days
            );
            while (true) {
                now_date = now_date+(userVesting.eachPeriod * 1 days);
                if (now_date < block.timestamp) {
                    tokenToBeUnlockPercent = tokenToBeUnlockPercent+(
                        userVesting.eachPercent
                    );
                    if (tokenToBeUnlockPercent >= 100) break;
                } else {
                    break;
                }
            }
            tokenToBeUnlockPercent = tokenToBeUnlockPercent > 100
                ? 100
                : tokenToBeUnlockPercent;

            tokenToBeUnlock = _amount*tokenToBeUnlockPercent/100;
            require(
                tokenToBeUnlock > unlockedVestingAmount[msg.sender],
                "nothing to unlock!"
            );
            uint256 tokenUnlocking = tokenToBeUnlock-unlockedVestingAmount[msg.sender];

            unlockedVestingAmount[msg.sender] = tokenToBeUnlock;
            ISpecialPool(payable(_pool)).sendToken(
                poolInformation.projectTokenAddress,
                tokenUnlocking,
                msg.sender
            );
        }
    }

    function collectFunds(
        address[4] calldata addresses,
        uint256[4] calldata amounts,
        ISpecialPool.PoolModel storage poolInformation,
        bool _isAdminSale
    ) external {
        SpecialValidatePoolLibrary._poolIsReadyCollect(
            poolInformation,
            amounts[0],
            addresses[0], addresses[3],
            _isAdminSale
        );
        if (!_isAdminSale) {
            IERC20 projectToken = IERC20(poolInformation.projectTokenAddress);
            uint256 totalToken = projectToken.balanceOf(addresses[0]);
            ISpecialPool(payable(addresses[0])).sendToken(
                poolInformation.projectTokenAddress,
                totalToken,
                addresses[0]
            );
            require(
                projectToken.balanceOf(addresses[0]) == totalToken,
                "remove tax"
            );

            // pay for the admin
            uint256 toAdminAmount = amounts[0]*amounts[1]/100;
            if (addresses[3] == address(0)) {
                if (toAdminAmount > 0)
                    ISpecialPool(payable(addresses[0])).sendETH(
                        toAdminAmount,
                        addresses[1]
                    );
                ISpecialPool(payable(addresses[0])).sendETH(
                    amounts[0]*(100 - amounts[1])/100,
                    addresses[2]
                );
            } else {
                if (toAdminAmount > 0)
                    ISpecialPool(payable(addresses[0])).sendToken(
                        addresses[3],
                        toAdminAmount,
                        addresses[1]
                    );
                ISpecialPool(payable(addresses[0])).sendToken(
                    addresses[3],
                    amounts[0]*(100 - amounts[1])/100,
                    addresses[2]
                );
            }

            toAdminAmount = projectToken
                .balanceOf(addresses[0])
                *(amounts[2])
                /(100 + amounts[2]);
            if (toAdminAmount > 0)
                ISpecialPool(payable(addresses[0])).sendToken(
                    poolInformation.projectTokenAddress,
                    toAdminAmount,
                    addresses[1]
                );

            uint256 rest = amounts[0]*poolInformation.specialSaleRate/(
                10**amounts[3]
            );

            rest = projectToken.balanceOf(addresses[0])-rest;
            if (rest > 0)
                ISpecialPool(payable(addresses[0])).sendToken(
                    poolInformation.projectTokenAddress,
                    rest,
                    addresses[2]
                );
        } else {
            if (addresses[3] == address(0)) {
                ISpecialPool(payable(addresses[0])).sendETH(
                    amounts[0],
                    addresses[2]
                );
            } else
                ISpecialPool(payable(addresses[0])).sendToken(
                    addresses[3],
                    amounts[0],
                    addresses[2]
                );
        }

        poolInformation.status = ISpecialPool.PoolStatus.Collected;
    }

    function refund(
        address _pool,
        uint256 _weiRaised,
        mapping(address => bool) storage _didRefund,
        mapping(address => uint256) storage collaborations,
        ISpecialPool.PoolModel storage poolInformation,
        address fundRaiseToken
    ) external {
        SpecialValidatePoolLibrary._poolIsCancelled(
            poolInformation,
            _weiRaised
        );
        if (_didRefund[msg.sender] != true && collaborations[msg.sender] > 0) {
            _didRefund[msg.sender] = true;
            if (fundRaiseToken == address(0))
                ISpecialPool(payable(_pool)).sendETH(
                    collaborations[msg.sender],
                    msg.sender
                );
            else
                ISpecialPool(payable(_pool)).sendToken(
                    fundRaiseToken,
                    collaborations[msg.sender],
                    msg.sender
                );
        }
    }

    function allowClaim(
        address[3] calldata addresses,
        uint256[2] calldata amount,
        ISpecialPool.PoolModel storage poolInformation,
        bool _isAdminSale,
        uint256 allowDateTime
    ) external {
        if (_isAdminSale) {
            IERC20 projectToken = IERC20(poolInformation.projectTokenAddress);
            uint256 totalToken = projectToken.balanceOf(addresses[0]);
            ISpecialPool(payable(addresses[0])).sendToken(
                poolInformation.projectTokenAddress,
                totalToken,
                addresses[0]
            );
            require(
                projectToken.balanceOf(addresses[0]) == totalToken,
                "remove tax"
            );

            uint256 rest = amount[0]*poolInformation.specialSaleRate/(
                10**amount[1]
            );

            rest = projectToken.balanceOf(addresses[0])-rest;
            if (rest > 0)
                ISpecialPool(payable(addresses[0])).sendToken(
                    poolInformation.projectTokenAddress,
                    rest,
                    addresses[1]
                );
        }
        SpecialValidatePoolLibrary._poolIsReadyAllow(poolInformation, allowDateTime);
        poolInformation.status = ISpecialPool.PoolStatus.Allowed;
    }
    function emergencyWithdraw(
        address _pool,
        address treasury,
        mapping(address => uint256) storage _weiRaised,
        mapping(address => uint256) storage collaborations,
        address[] storage participantsAddress,
        ISpecialPool.PoolModel storage poolInformation,
        address fundRaiseToken
    ) external returns (bool) {
        SpecialValidatePoolLibrary._poolIsOngoing(poolInformation);
        require(
            _weiRaised[_pool] < poolInformation.hardCap &&
                poolInformation.endDateTime >= block.timestamp + 1 hours,
            "sale finished"
        );
        if (collaborations[msg.sender] > 0) {
            _weiRaised[_pool] = _weiRaised[_pool]-collaborations[msg.sender];

            uint256 withdrawAmount = collaborations[msg.sender]*9/10;
            uint256 feeAmount = collaborations[msg.sender] - withdrawAmount;
            if (fundRaiseToken == address(0)) {
                ISpecialPool(payable(_pool)).sendETH(withdrawAmount, msg.sender);
                ISpecialPool(payable(_pool)).sendETH(feeAmount, treasury);
            } else {
                ISpecialPool(payable(_pool)).sendToken(
                    fundRaiseToken,
                    withdrawAmount,
                    msg.sender
                );
                ISpecialPool(payable(_pool)).sendToken(
                    fundRaiseToken,
                    feeAmount,
                    treasury
                );
            }

            for (uint256 i = 0; i < participantsAddress.length - 1; i++) {
                if (participantsAddress[i] == msg.sender) {
                    for (
                        uint256 k = i;
                        k < participantsAddress.length - 1;
                        k++
                    ) {
                        participantsAddress[k] = participantsAddress[k + 1];
                    }
                    break;
                }
            }
            participantsAddress.pop();
            collaborations[msg.sender] = 0;
            return true;
        }
        return false;
    }
}

