// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./Ownable.sol";

import "./IVoteDashboard.sol";
import "./IDashboard.sol";
import "./IPriceCalculator.sol";
import "./IVoteController.sol";
import "./ILocker.sol";
import "./IGToken.sol";
import "./IBEP20.sol";
import "./IGRVDistributor.sol";

contract VoteDashboard is IVoteDashboard, Ownable {
    using SafeMath for uint256;

    uint256 private constant weekUnit = uint256(60 * 60 * 24 * 7);
    uint256 private constant divider = 1e18 * weekUnit;

    /* ========== STATE VARIABLES ========== */

    IVoteController public voteController;
    ILocker public locker;
    IGRVDistributor public grvDistributor;
    IDashboard public dashboard;
    IPriceCalculator public priceCalculator;

    uint256 public totalWeekEmission;

    /* ========== INITIALIZER ========== */

    constructor(address _voteController, address _locker, address _grvDistributor,
                address _dashboard, address _priceCalculator, uint256 _totalWeekEmission) public {
        voteController = IVoteController(_voteController);
        locker = ILocker(_locker);
        grvDistributor = IGRVDistributor(_grvDistributor);
        dashboard = IDashboard(_dashboard);
        priceCalculator = IPriceCalculator(_priceCalculator);
        totalWeekEmission = _totalWeekEmission;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTotalWeekEmission(uint256 _totalWeekEmission) external onlyOwner {
        totalWeekEmission = _totalWeekEmission;
    }

    /* ========== VIEWS ========== */

    function votedGrvInfo(address user) external view override returns (VotedGrvInfo memory) {
        VotedGrvInfo memory _votedGrvInfo;
        (uint256 _totalScore, ) = locker.totalScore();
        uint256 _totalVotedGrvAmount = voteController.totalSupply();
        uint256 _totalVotedGrvRatio = _totalVotedGrvAmount.mul(1e18).div(_totalScore);

        uint256 _myScore = 0;
        uint256 _myVotedGrvAmount = 0;
        uint256 _myVotedGrvRatio = 0;

        if (user != address(0)) {
            _myScore = locker.scoreOf(user);
            _myVotedGrvAmount = voteController.balanceOf(user);
            _myVotedGrvRatio = _myVotedGrvAmount >= _myScore ? 1e18 : _myVotedGrvAmount.mul(1e18).div(_myScore);
        }

        _votedGrvInfo.totalVotedGrvAmount = _totalVotedGrvAmount;
        _votedGrvInfo.totalVotedGrvRatio = _totalVotedGrvRatio;
        _votedGrvInfo.myVotedGrvAmount = _myVotedGrvAmount;
        _votedGrvInfo.myVotedGrvRatio = _myVotedGrvRatio;

        return _votedGrvInfo;
    }

    function votingStatus(address user) external view override returns (VotingStatus[] memory) {
        address[] memory pools = voteController.getPools();
        VotingStatus[] memory _votingStatus = new VotingStatus[](pools.length);

        uint256 totalVotedGrvAmount = voteController.totalSupply();

        for (uint256 i = 0; i < pools.length; i++) {
            string memory symbol = _getSymbol(pools[i]);
            uint256 userWeight = voteController.userWeights(user, pools[i]);
            uint256 poolVotedAmount = voteController.sumAtTimestamp(pools[i], block.timestamp);
            uint256 poolVotedRate = totalVotedGrvAmount > 0 ? poolVotedAmount.mul(1e18).div(totalVotedGrvAmount) : 0;

            Constant.DistributionAPY memory apyDistribution = grvDistributor.apyDistributionOf(pools[i], address(0));
            uint256 poolSpeed = totalWeekEmission.mul(poolVotedRate).div(divider);
            uint256 supplySpeed = poolSpeed.mul(1e18).div(3e18);
            uint256 borrowSpeed = poolSpeed.mul(2e18).div(3e18);
            (uint256 toApySupplyGRV, uint256 toApyBorrowGRV) = _calculateMarketDistributionAPY(pools[i], supplySpeed, borrowSpeed);

            _votingStatus[i].symbol = symbol;
            _votingStatus[i].userWeight = userWeight;
            _votingStatus[i].poolVotedRate = poolVotedRate;
            _votingStatus[i].fromGrvSupplyAPR = apyDistribution.apySupplyGRV;
            _votingStatus[i].fromGrvBorrowAPR = apyDistribution.apyBorrowGRV;
            _votingStatus[i].toGrvSupplyAPR = toApySupplyGRV;
            _votingStatus[i].toGrvBorrowAPR = toApyBorrowGRV;
        }
        return _votingStatus;
    }

    function _calculateMarketDistributionAPY(
        address market,
        uint256 supplySpeed,
        uint256 borrowSpeed
    ) private view returns (uint256 apySupplyGRV, uint256 apyBorrowGRV) {
        address _market = market;
        uint256 decimals = _getDecimals(_market);
        // base supply GRV APY == average supply GRV APY * (Total balance / total Boosted balance)
        // base supply GRV APY == (GRVRate * 365 days * price Of GRV) / (Total balance * exchangeRate * price of asset) * (Total balance / Total Boosted balance)
        // base supply GRV APY == (GRVRate * 365 days * price Of GRV) / (Total boosted balance * exchangeRate * price of asset)
        {
            uint256 numerSupply = supplySpeed.mul(365 days).mul(dashboard.getCurrentGRVPrice());
            uint256 denomSupply = grvDistributor.distributionInfoOf(_market)
            .totalBoostedSupply
            .mul(10 ** (18 - decimals))
            .mul(IGToken(_market).exchangeRate())
            .mul(priceCalculator.getUnderlyingPrice(_market))
            .div(1e36);
            apySupplyGRV = denomSupply > 0 ? numerSupply.div(denomSupply) : 0;
        }

        // base borrow GRV APY == average borrow GRV APY * (Total balance / total Boosted balance)
        // base borrow GRV APY == (GRVRate * 365 days * price Of GRV) / (Total balance * exchangeRate * price of asset) * (Total balance / Total Boosted balance)
        // base borrow GRV APY == (GRVRate * 365 days * price Of GRV) / (Total boosted balance * exchangeRate * price of asset)
        {
            uint256 numerBorrow = borrowSpeed.mul(365 days).mul(dashboard.getCurrentGRVPrice());
            uint256 denomBorrow = grvDistributor.distributionInfoOf(_market)
            .totalBoostedBorrow
            .mul(10 ** (18 - decimals))
            .mul(IGToken(_market).getAccInterestIndex())
            .mul(priceCalculator.getUnderlyingPrice(_market))
            .div(1e36);
            apyBorrowGRV = denomBorrow > 0 ? numerBorrow.div(denomBorrow) : 0;
        }
    }

    function _getSymbol(address gToken) internal view returns (string memory symbol) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            symbol = "ETH";
        } else {
            symbol = IBEP20(underlying).symbol();
        }
    }

    function _getDecimals(address gToken) internal view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18;
            // ETH
        } else {
            decimals = IBEP20(underlying).decimals();
        }
    }
}

