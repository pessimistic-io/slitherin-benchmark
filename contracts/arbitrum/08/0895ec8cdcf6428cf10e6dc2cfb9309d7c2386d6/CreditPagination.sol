// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Ownable } from "./Ownable.sol";

import { ICreditCaller as IOriginCreditCaller } from "./ICreditCaller.sol";
import { ICreditUser } from "./ICreditUser.sol";
import { ICreditAggregator } from "./ICreditAggregator.sol";

interface IGmxGlpManager {
    function getAum(bool maximise) external view returns (uint256);
}

interface IGmxVault {
    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);
}

interface IGmxStakedGlp {
    function totalSupply() external view returns (uint256);
}

interface IGmxRewardTracker {
    function tokensPerInterval() external view returns (uint256);
}

interface ICreditCaller is IOriginCreditCaller {
    function creditUser() external view returns (address);

    function getUserCreditHealth(address _recipient, uint256 _borrowedIndex) external view returns (uint256);
}

interface IVaultRewardDistributors {
    function borrowedRewardPoolRatio() external view returns (uint256);
}

contract CreditPagination is Ownable {
    uint256 private constant ONE_YEAR = 31536000;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant STAKED_GLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;
    uint256 private constant MAX_LOAN_DURATION = 1 days * 365;

    address public gmxGlpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public gmxStakedGlp = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
    address public gmxRewardTracker = 0x4e971a87900b931fF39d1Aad67697F49835400b6;
    address public gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address public creditAggregator = 0xeD36E66ad87dE148A908e8a51b78888553D87E16;

    mapping(address => address) public vaultRewardsDistributors;

    struct UserLendCredit {
        address depositor;
        address token;
        uint256 amountIn;
        uint256 reservedLiquidatorFee;
        address[] borrowedTokens;
        uint256[] ratios;
        uint256 health;
        uint256 timeoutTimestamp;
        bool terminated;
    }

    struct UserBorrowed {
        address[] creditManagers;
        uint256[] borrowedAmountOuts;
        uint256 collateralMintedAmount;
        uint256[] borrowedMintedAmount;
        uint256 mintedAmount;
    }

    struct UserPosition {
        address creditCaller;
        uint256 borrowedIndex;
        UserLendCredit userLendCredit;
        UserBorrowed userBorrowed;
    }

    struct GeneralPosition {
        uint256 totalPositions;
        uint256[] userCounts;
        LendCreditMapping[] lendCreditMappings;
        uint256 size;
        bool hasNext;
    }

    struct LendCreditMapping {
        address creditCaller;
        address creditUser;
        uint256 borrowedIndex;
        address recipient;
    }

    struct ReturnPosition {
        uint256 positionApr;
        uint256 gmxApr;
        uint256 withdrawBalance;
        address creditCaller;
        uint256 borrowedIndex;
        UserLendCredit userLendCredits;
        UserBorrowed userBorroweds;
    }

    function _getCreditUsers(address[] calldata _creditCallers) internal view returns (address[] memory) {
        address[] memory creditUsers = new address[](_creditCallers.length);

        for (uint256 i = 0; i < _creditCallers.length; i++) {
            creditUsers[i] = ICreditCaller(_creditCallers[i]).creditUser();
        }

        return creditUsers;
    }

    function _getGeneralPosition(
        address[] memory _creditCallers,
        address[] memory _creditUsers,
        address _recipient,
        uint256 _offset,
        uint256 _size
    ) internal view returns (GeneralPosition memory generalPosition) {
        generalPosition.userCounts = new uint256[](_creditUsers.length);

        for (uint256 i = 0; i < _creditUsers.length; i++) {
            generalPosition.userCounts[i] = ICreditUser(_creditUsers[i]).getUserCounts(_recipient);
            generalPosition.totalPositions += generalPosition.userCounts[i];
        }

        (generalPosition.size, generalPosition.hasNext) = _getCursor(generalPosition.totalPositions, _offset, _size);

        generalPosition.lendCreditMappings = _getLendCreditMapping(
            generalPosition.totalPositions,
            generalPosition.userCounts,
            _creditCallers,
            _creditUsers,
            _recipient
        );
    }

    function _getCursor(uint256 _totalSize, uint256 _offset, uint256 _size) internal pure returns (uint256 size, bool hasNext) {
        if (_offset >= _totalSize) {
            size = 0;
            hasNext = false;
        } else if (_offset + _size > _totalSize) {
            size = _totalSize - _offset;
            hasNext = false;
        } else {
            size = _size;
            hasNext = true;
        }
    }

    function getCreditPagination(
        address[] calldata _creditCallers,
        address _recipient,
        uint256 _offset,
        uint256 _size
    ) public view returns (ReturnPosition[] memory, uint256, bool) {
        require(_creditCallers.length > 0, "CreditPagination: Length mismatch");
        require(_recipient != address(0), "CreditPagination: _recipient cannot be 0x0");
        require(_size > 0, "CreditPagination: _size cannot be 0");

        address[] memory creditUsers = _getCreditUsers(_creditCallers);
        GeneralPosition memory generalPosition = _getGeneralPosition(_creditCallers, creditUsers, _recipient, _offset, _size);
        UserPosition[] memory userPositions = _getPagination(generalPosition.lendCreditMappings, _offset, generalPosition.size);

        return (_calcUserPositions(userPositions), generalPosition.size, generalPosition.hasNext);
    }

    function _getPagination(LendCreditMapping[] memory _lendCreditMappings, uint256 _offset, uint256 _size) internal view returns (UserPosition[] memory) {
        UserPosition[] memory userPositions = new UserPosition[](_size);

        uint256 borrowedIndex = 0;

        for (uint256 i = 0; i < _lendCreditMappings.length; i++) {
            if (i < _offset) continue;
            if (borrowedIndex == _size) break;

            userPositions[borrowedIndex].creditCaller = _lendCreditMappings[i].creditCaller;
            userPositions[borrowedIndex].borrowedIndex = _lendCreditMappings[i].borrowedIndex;
            userPositions[borrowedIndex].userLendCredit = _getUserLendCredit(
                _lendCreditMappings[i].creditCaller,
                _lendCreditMappings[i].creditUser,
                _lendCreditMappings[i].recipient,
                _lendCreditMappings[i].borrowedIndex
            );
            userPositions[borrowedIndex].userBorrowed = _getUserBorrowed(
                _lendCreditMappings[i].creditUser,
                _lendCreditMappings[i].recipient,
                _lendCreditMappings[i].borrowedIndex
            );

            borrowedIndex++;
        }

        return userPositions;
    }

    function _getLendCreditMapping(
        uint256 _totalPositions,
        uint256[] memory _userCount,
        address[] memory _creditCallers,
        address[] memory _creditUsers,
        address _recipient
    ) internal pure returns (LendCreditMapping[] memory) {
        LendCreditMapping[] memory lendCreditMappings = new LendCreditMapping[](_totalPositions);
        uint256 borrowedIndex = 0;

        for (uint256 i = 0; i < _creditCallers.length; i++) {
            for (uint256 j = 0; j < _userCount[i]; j++) {
                lendCreditMappings[borrowedIndex].creditCaller = _creditCallers[i];
                lendCreditMappings[borrowedIndex].creditUser = _creditUsers[i];
                lendCreditMappings[borrowedIndex].borrowedIndex = j + 1;
                lendCreditMappings[borrowedIndex].recipient = _recipient;
                borrowedIndex++;
            }
        }

        return lendCreditMappings;
    }

    function _calcUserPositions(UserPosition[] memory userPositions) internal view returns (ReturnPosition[] memory) {
        ReturnPosition[] memory returnPositions = new ReturnPosition[](userPositions.length);

        uint256 gmxApr = fetchGmxApr();

        for (uint256 i = 0; i < userPositions.length; i++) {
            uint256 positionApr = 0;
            uint256 withdrawBalance = 0;

            if (!userPositions[i].userLendCredit.terminated) {
                positionApr = _calcPositionApr(gmxApr, userPositions[i].userLendCredit);
                withdrawBalance = _calcWithdrawBalance(userPositions[i].userLendCredit, userPositions[i].userBorrowed);
            }

            returnPositions[i] = ReturnPosition({
                gmxApr: gmxApr,
                creditCaller: userPositions[i].creditCaller,
                borrowedIndex: userPositions[i].borrowedIndex,
                positionApr: positionApr,
                withdrawBalance: withdrawBalance,
                userLendCredits: userPositions[i].userLendCredit,
                userBorroweds: userPositions[i].userBorrowed
            });
        }

        return returnPositions;
    }

    function _calcPositionApr(uint256 _gmxApr, UserLendCredit memory _lendCredit) internal view returns (uint256 apr) {
        apr = _gmxApr;

        for (uint256 i = 0; i < _lendCredit.ratios.length; i++) {
            address borrowedToken = _lendCredit.borrowedTokens[i];
            uint256 baseApr = (_gmxApr * IVaultRewardDistributors(vaultRewardsDistributors[borrowedToken]).borrowedRewardPoolRatio()) / 1000;
            apr += (_lendCredit.ratios[i] * baseApr) / 100;
        }
    }

    function _calcWithdrawBalance(UserLendCredit memory _lendCredit, UserBorrowed memory _borrowed) internal view returns (uint256) {
        uint256 totalMintedAmounts = _borrowed.mintedAmount;

        for (uint256 i = 0; i < _lendCredit.borrowedTokens.length; i++) {
            (uint256 amountOut, ) = ICreditAggregator(creditAggregator).getSellGlpFromAmount(_lendCredit.borrowedTokens[i], _borrowed.borrowedAmountOuts[i]);

            if (totalMintedAmounts > amountOut) {
                totalMintedAmounts -= amountOut;
            } else {
                totalMintedAmounts = 0;
                break;
            }
        }

        if (_lendCredit.token == STAKED_GLP || totalMintedAmounts == 0) {
            return totalMintedAmounts;
        }

        (uint256 amounts, ) = ICreditAggregator(creditAggregator).getSellGlpToAmount(_lendCredit.token, totalMintedAmounts);

        return amounts;
    }

    function _getUserLendCredit(
        address _creditCaller,
        address _creditUser,
        address _recipient,
        uint256 _borrowedIndex
    ) internal view returns (UserLendCredit memory) {
        (
            address depositor,
            address token,
            uint256 amountIn,
            uint256 reservedLiquidatorFee,
            address[] memory borrowedTokens,
            uint256[] memory ratios
        ) = ICreditUser(_creditUser).getUserLendCredit(_recipient, _borrowedIndex);

        bool terminated = ICreditUser(_creditUser).isTerminated(_recipient, _borrowedIndex);

        return
            UserLendCredit({
                depositor: depositor,
                token: token,
                amountIn: amountIn,
                reservedLiquidatorFee: reservedLiquidatorFee,
                borrowedTokens: borrowedTokens,
                ratios: ratios,
                terminated: terminated,
                timeoutTimestamp: ICreditUser(_creditUser).getTimeoutTimestamp(_recipient, _borrowedIndex, MAX_LOAN_DURATION),
                health: !terminated ? ICreditCaller(_creditCaller).getUserCreditHealth(_recipient, _borrowedIndex) : 0
            });
    }

    function _getUserBorrowed(address _creditUser, address _recipient, uint256 _borrowedIndex) internal view returns (UserBorrowed memory) {
        (
            address[] memory creditManagers,
            uint256[] memory borrowedAmountOuts,
            uint256 collateralMintedAmount,
            uint256[] memory borrowedMintedAmount,
            uint256 mintedAmount
        ) = ICreditUser(_creditUser).getUserBorrowed(_recipient, _borrowedIndex);

        return
            UserBorrowed({
                creditManagers: creditManagers,
                borrowedAmountOuts: borrowedAmountOuts,
                collateralMintedAmount: collateralMintedAmount,
                borrowedMintedAmount: borrowedMintedAmount,
                mintedAmount: mintedAmount
            });
    }

    function fetchGmxApr() public view returns (uint256 apr) {
        uint256 totalGlpSupply = IGmxStakedGlp(gmxStakedGlp).totalSupply();
        uint256 tokensPerInterval = IGmxRewardTracker(gmxRewardTracker).tokensPerInterval();
        uint256 wethPrice = IGmxVault(gmxVault).getMinPrice(WETH);
        uint256 glpPrice = ICreditAggregator(creditAggregator).getGlpPrice(false);
        uint256 glpSupplyUsd = totalGlpSupply * glpPrice;

        uint256 annualRewardsUsd = tokensPerInterval * ONE_YEAR * wethPrice;

        apr = (annualRewardsUsd * 10000) / glpSupplyUsd; // 1242
    }

    function setVaultRewardsDistributor(address _borrowedToken, address _rewardDistributor) public onlyOwner {
        require(_borrowedToken != address(0), "CreditPagination: _borrowedToken cannot be 0x0");
        require(_rewardDistributor != address(0), "CreditPagination: _rewardDistributor cannot be 0x0");

        vaultRewardsDistributors[_borrowedToken] = _rewardDistributor;
    }
}

