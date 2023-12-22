// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { IERC20 } from "./ERC20_IERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./IRebateEstimator.sol";
import "./ERC20_IERC20.sol";
import { IStaking, UserStake } from "./IStaking.sol";
import { ITimeWeightedAveragePricer } from "./ITimeWeightedAveragePricer.sol";
import { ISnapshottable } from "./ISnapshottable.sol";


struct RebateTier {
    uint256 value;
    uint64 rebate;
    uint24 dexShareFactor;
}


contract TierController is Ownable, IRebateEstimator, ISnapshottable {
    using SafeMath for uint256;

    uint24 public constant FACTOR_DIVISOR = 100000;

    IStaking public staking;
    ITimeWeightedAveragePricer public pricer;
    RebateTier[] public rebateTiers;
    address public token;
    IRebateEstimator internal rebateAlternatives;

    mapping (address => bool) public isSnapshotter;


    constructor(
        address _token,
        address _staking,
        address _pricer,
        RebateTier[] memory _rebateTiers
    ) {
        token = _token;
        setPricer(ITimeWeightedAveragePricer(_pricer));
        setStaking(IStaking(_staking));
        setTiers(_rebateTiers);
    }


    ///////////////////////////////////////
    // View functions
    ///////////////////////////////////////

    function tierToHumanReadable(RebateTier memory tier) public view returns (uint256[] memory output) {
        output = new uint256[](3);
        output[0] = uint256(tier.value).div(10**IERC20Uniswap(address(pricer.token1())).decimals());
        output[1] = tier.rebate;
        output[2] = uint256(tier.dexShareFactor).div(10);
    }
    function getHumanReadableTiers() public view returns (uint256[][] memory output) {
        output = new uint256[][](uint256(rebateTiers.length));
        uint256 invI = 0;
        for (int256 i = int256(rebateTiers.length) - 1;  i >= 0;  --i) {
            output[invI] = tierToHumanReadable(rebateTiers[uint256(i)]);
            invI = invI.add(1);
        }
    }
    function getAllTiers() public view returns (RebateTier[] memory) {
        return rebateTiers;
    }
    function getTierCount() public view returns (uint8) {
        return uint8(rebateTiers.length);
    }
    function getUserTokenValue(address account) public view returns (uint256) {
        uint256 vestedTokens = staking.getVestedTokens(account);
        uint256 value = pricer.getToken0Value(vestedTokens);
        return value;
    }
    function getUserTokenValue(uint256 _blockNumber, address _account) public view returns (uint256) {
        uint256 _vestedTokens = staking.getVestedTokensAtSnapshot(_account, _blockNumber);
        uint256 _value = pricer.getToken0ValueAtSnapshot(_blockNumber, _vestedTokens);
        return _value;
    }
    function getHumanReadableTier(address account) public view returns (uint256, uint[] memory) {
        (uint256 i, RebateTier memory tier) = getTier(account);
        return (i, tierToHumanReadable(tier));
    }
    function getTier(address account) public view returns (uint8, RebateTier memory) {
        uint8 idx = getTierIdx(account);
        return (idx, rebateTiers[idx]);
    }
    function getTierIdx(address account) public view returns (uint8) {
        uint256 value = getUserTokenValue(account);
        uint8 len = uint8(rebateTiers.length);
        for (uint8 i = 0; i < len; i++) {
            if (value >= rebateTiers[i].value) {
                return i;
            }
        }

        // this should be logically impossible
        require(false, "TierController: no rebate tier applicable");
        return 0; // to make compiler happy
    }
    function getTierIdx(uint256 _blockNumber, address _account) public view returns (uint8) {
        uint256 value = getUserTokenValue(_blockNumber, _account);
        uint8 len = uint8(rebateTiers.length);
        for (uint8 i = 0; i < len; i++) {
            if (value >= rebateTiers[i].value) {
                return i;
            }
        }

        // this should be logically impossible
        require(false, "TierController: no rebate tier applicable");
        return 0; // to make compiler happy
    }
    function getDexShareFactor(address account) public view returns (uint24) {
        uint256 i;
        RebateTier memory tier;
        (i, tier) = getTier(account);
        return tier.dexShareFactor;
    }
    function getRebate(address account) external override view returns (uint64) {
        uint64 rebateAlternative = 0;
        if (address(rebateAlternatives) != address(0)) {
            rebateAlternative = rebateAlternatives.getRebate(account);
        }

        uint256 i;
        RebateTier memory tier;
        (i, tier) = getTier(account);

        return uint64(Math.max(tier.rebate, rebateAlternative));
    }


    ///////////////////////////////////////
    // Housekeeping
    ///////////////////////////////////////

    function snapshot() external onlySnapshotter override {
        pricer.snapshot();
        staking.snapshot();
    }
    function setSnapshotter(address _snapshotter, bool _state) external onlyOwner {
        isSnapshotter[_snapshotter] = _state;
    }
    modifier onlySnapshotter() {
        require(isSnapshotter[msg.sender], "Only snapshotter can call this function");
        _;
    }

    function setPricer(ITimeWeightedAveragePricer _pricer) public onlyOwner {
        require(address(_pricer) != address(0), "TierController: pricer contract cannot be 0x0");
        require(token == address(_pricer.token0()), "TierController: staking token mismatch 1");
        pricer = _pricer;
    }
    function setStaking(IStaking _staking) public onlyOwner {
        require(address(_staking) != address(0), "TierController: staking contract cannot be 0x0");
        require(token == address(_staking.token()), "TierController: staking token mismatch 2");
        staking = _staking;
    }
    function setOwner(address _newOwner) external onlyOwner {
        transferOwnership(_newOwner);
    }
    function setRebateAlternatives(IRebateEstimator _rebateAlternatives) external onlyOwner {
        rebateAlternatives = _rebateAlternatives;
    }
    function setTiers(RebateTier[] memory _rebateTiers) public onlyOwner {
        require(_rebateTiers.length > 0, "TierController: rebate tiers list cannot be empty");
        require(_rebateTiers[_rebateTiers.length - 1].value == 0, "TierController: last rebate tier value must be 0");
        require(_rebateTiers.length < type(uint8).max, "TierController: rebate tiers list too long");
        require(_rebateTiers.length == rebateTiers.length || rebateTiers.length == 0, "TierController: can't change number of tiers");

        delete rebateTiers;
        for (uint256 i = 0; i < _rebateTiers.length; i++) {
            require(_rebateTiers[i].rebate <= 10000, "TierController: rebate must be 10000 or less");

            if (i > 0) {
                require(_rebateTiers[i].value < _rebateTiers[i.sub(1)].value, "TierController: rebate tiers list is not sorted in descending order");
            }
            require(_rebateTiers[i].dexShareFactor <= FACTOR_DIVISOR, "TierController: dex share factors must not exceed FACTOR_DIVISOR");

            // set inside loop because not supported by compiler to copy whole array in one
            rebateTiers.push(_rebateTiers[i]);
        }
        require(rebateTiers[0].dexShareFactor == FACTOR_DIVISOR, "TierController: dex share factors must max out at FACTOR_DIVISOR");
    }
}

