// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Math.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./IUnderlying.sol";
import "./IVoter.sol";
import "./IVe.sol";
import "./IVeDist.sol";
import "./IMinter.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IController.sol";
import "./ReentrancyUpgradeable.sol";

// import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Codifies the minting rules as per ve(3,3),
///        abstracted from the token to support any token that allows minting
contract Minter is IMinter, Initializable, ReentrancyUpgradeable /* UUPSUpgradeable, OwnableUpgradeable */ {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Allows minting once per week (every Thursday UTC 00:00)
    uint256 public _week;
    /// @dev Offset the epoch by +42h (Friday UTC 18:00)
    uint256 internal constant _WEEK_OFFSET = 42 * 60 * 60;
    uint256 internal constant _LOCK_PERIOD = 86400 * 7 * 52;

    /// @dev Decrease base weekly emission by 3%
    uint256 internal constant _WEEKLY_EMISSION_DECREASE = 97;
    uint256 internal constant _WEEKLY_EMISSION_DECREASE_DENOMINATOR = 100;

    /// @dev Weekly emission threshold for the end game. 1% of circulation supply.
    uint256 internal constant _TAIL_EMISSION = 1;
    uint256 internal constant _TAIL_EMISSION_DENOMINATOR = 100;

    /// @dev Decrease weekly rewards for ve holders. 12.5% of the full amount.
    uint256 internal constant _GROWTH_DIVIDER = 8;

    /// @dev 5% goes to governance to maintain the platform.
    uint internal constant _GOVERNANCE_ALLOC = 20;

    /// @dev Decrease initialStubCirculationSupply by 1% per fortnight.
    ///      Decreasing only if circulation supply lower that the stub circulation
    uint256 internal constant _INITIAL_CIRCULATION_DECREASE = 99;
    uint256 internal constant _INITIAL_CIRCULATION_DECREASE_DENOMINATOR = 100;

    /// @dev Stubbed initial circulating supply to avoid first weeks gaps of locked amounts.
    ///      Should be equal expected unlocked token percent.
    uint256 internal constant _STUB_CIRCULATION = 10;
    uint256 internal constant _STUB_CIRCULATION_DENOMINATOR = 100;

    /// @dev The core parameter for determinate the whole emission dynamic.
    ///       Will be decreased every fortnight.
    uint256 internal constant _START_BASE_WEEKLY_EMISSION = 1_100_000e18;

    ///@dev claimable for airdrop (address => amount)
    // mapping(address => uint) public claimable;

    IUnderlying public token;
    IVe public ve;
    address public controller;
    bool public firstEmission;
    uint256 public baseWeeklyEmission;
    uint256 public initialStubCirculation;
    uint256 public bootstrapPeriodEnd;
    uint256 public activePeriod;

    address internal postInitializer;
    address public admin;

    event Mint(address indexed sender, uint256 weekly, uint256 growth, uint256 toGovernance, uint256 circulatingSupply, uint256 circulatingEmission);
    event Claimed(uint amount, address receiver);

    function initialize(
        address ve_, // the ve(3,3) system that will be locked into
        address controller_, // controller with veDist and voter addresses
        uint256 warmingUpPeriod
    ) public initializer {
        _week = 86400 * 7;
        postInitializer = msg.sender;
        admin = msg.sender;
        token = IUnderlying(IVe(ve_).token());
        ve = IVe(ve_);
        controller = controller_;
        firstEmission = true;
        activePeriod = block.timestamp + warmingUpPeriod;
        baseWeeklyEmission = _START_BASE_WEEKLY_EMISSION;
    }

    /// @dev Mint initial supply to holders and lock it to ve token.
    function postInitialize() external {
        require(postInitializer == msg.sender, "Not initializer");
        activePeriod = block.timestamp;
        // for first epoch, consider week as 0
        _week = 0;
        // premint 50m for initial distribution
        token.mint(msg.sender, 50000000e18);
        postInitializer = address(0);
    }

    // function claim() external {
    //     require(claimable[_msgSender()] > 0, "You have already claimed or not eligible");
    //     address claimer = _msgSender();
    //     uint sendAmount = claimable[claimer];
    //     claimable[claimer] -= sendAmount;
    //     ve.createLockFor(sendAmount, _LOCK_PERIOD, claimer);
    //     emit Claimed(sendAmount, claimer);
    // }

    function _veDist() internal view returns (IVeDist) {
        return IVeDist(IController(controller).veDist());
    }

    function _voter() internal view returns (IVoter) {
        return IVoter(IController(controller).voter());
    }

    /// @dev Calculate circulating supply as total token supply - locked supply - veDist balance - minter balance
    function circulatingSupply() external view returns (uint256) {
        return _circulatingSupply();
    }

    function _circulatingSupply() internal view returns (uint256) {
        return
            token.totalSupply() -
            IUnderlying(address(ve)).totalSupply() -
            // exclude veDist token balance from circulation - users unable to claim them without lock
            // late claim will lead to wrong circulation supply calculation
            token.balanceOf(address(_veDist())) -
            // exclude balance on minter, it is obviously locked
            token.balanceOf(address(this));
    }

    function _circulatingSupplyAdjusted() internal view returns (uint256) {
        // we need a stub supply for cover initial gap when huge amount of tokens was distributed and locked
        return Math.max(_circulatingSupply(), initialStubCirculation);
    }

    /// @dev Emission calculation is 2% of available supply to mint adjusted by circulating / total supply
    function calculateEmission() external view returns (uint256) {
        return _calculateEmission();
    }

    function _calculateEmission() internal view returns (uint256) {
        // use adjusted circulation supply for avoid first weeks gaps
        // baseWeeklyEmission should be decrease every week
        if (block.timestamp < bootstrapPeriodEnd) {
            return baseWeeklyEmission;
        }
        return (baseWeeklyEmission * _circulatingSupplyAdjusted()) / token.totalSupply();
    }

    /// @dev Weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weeklyEmission() external view returns (uint256) {
        return _weeklyEmission();
    }

    function _weeklyEmission() internal view returns (uint256) {
        return Math.max(_calculateEmission(), _circulatingEmission());
    }

    /// @dev Calculates tail end (infinity) emissions as 0.2% of total supply
    function circulatingEmission() external pure returns (uint256) {
        // return _circulatingEmission();
        return 0;
    }

    function _circulatingEmission() internal pure returns (uint256) {
        // return (_circulatingSupply() * _TAIL_EMISSION) / _TAIL_EMISSION_DENOMINATOR;
        return 0;
    }

    /// @dev Calculate inflation and adjust ve balances accordingly
    function calculateGrowth(uint256 _minted) external view returns (uint256) {
        return _calculateGrowth(_minted);
    }

    function _calculateGrowth(uint256 _minted) internal view returns (uint256) {
        return (IUnderlying(address(ve)).totalSupply() * _minted) / token.totalSupply() / _GROWTH_DIVIDER;
    }

    function _timestampToRoundedEpoch(uint256 _ts) internal pure returns (uint256) {
        uint256 w = 7 * 24 * 60 * 60;
        uint256 rounded = (((_ts - _WEEK_OFFSET) / w) * w) + _WEEK_OFFSET;
        if ((_ts - rounded) > w) rounded = rounded + w;
        return rounded;
    }

    /// @dev Update period can only be called once per cycle (1 week)
    function updatePeriod() external override returns (uint256) {
        uint256 _period = activePeriod;
        if (firstEmission) {
            require(msg.sender == admin);
        }
        // only trigger if new fortnight
        if (block.timestamp >= _period + _week && postInitializer == address(0)) {
            _week = 86400 * 7;
            _period = _timestampToRoundedEpoch(block.timestamp);
            activePeriod = _period;
            uint256 _weekly = _weeklyEmission();
            // slightly decrease fortnights emission
            baseWeeklyEmission = (baseWeeklyEmission * _WEEKLY_EMISSION_DECREASE) / _WEEKLY_EMISSION_DECREASE_DENOMINATOR;
            // decrease stub supply every fortnight if it higher than the real circulation
            if (initialStubCirculation > _circulatingEmission()) {
                initialStubCirculation = (initialStubCirculation * _INITIAL_CIRCULATION_DECREASE) / _INITIAL_CIRCULATION_DECREASE_DENOMINATOR;
            }

            // No emissions in first week to ve
            uint256 _growth = _calculateGrowth(_weekly);
            if (firstEmission) {
                firstEmission = false;
                // No emissions in first week to ve
                _growth = 0;
                // Set bootstrap phase as first 2 weeks
                bootstrapPeriodEnd = _period + (2 * _week);
            }
            uint toGovernance = _growth + _weekly / _GOVERNANCE_ALLOC;
            uint _required = _growth + _weekly + toGovernance;
            uint256 _balanceOf = token.balanceOf(address(this));
            if (_balanceOf < _required) {
                token.mint(address(this), _required - _balanceOf);
            }

            IERC20Upgradeable(address(token)).safeTransfer(IController(controller).governance(), toGovernance);
            if (_growth > 0) {
                IERC20Upgradeable(address(token)).safeTransfer(address(_veDist()), _growth);
            }
            // checkpoint token balance that was just minted in veDist
            _veDist().checkpointToken();
            // checkpoint supply
            _veDist().checkpointTotalSupply();

            token.approve(address(_voter()), _weekly);
            _voter().notifyRewardAmount(_weekly);

            emit Mint(msg.sender, _weekly, _growth, toGovernance, _circulatingSupply(), _circulatingEmission());
        }
        return _period;
    }
}

