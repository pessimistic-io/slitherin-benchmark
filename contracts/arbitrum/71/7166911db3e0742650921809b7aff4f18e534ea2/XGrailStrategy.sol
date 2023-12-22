//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./IXGrail.sol";
import "./IXGrailTokenUsage.sol";
import "./IDividendsV2.sol";
import "./ICamelotPair.sol";
import "./ICamelotRouter.sol";
import "./IYieldBooster.sol";
import "./IUniversalLiquidator.sol";

contract XGrailStrategy is BaseUpgradeableStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct TargetAllocation {
        address allocationAddress; // Address to allocate too
        uint256 weight;            // Weight of allocation (in BPS)
        bytes data;                // Bytes to send in the usageData field
    }

    struct CurrentAllocation {
        address allocationAddress; // Address to allocate too
        uint256 amount;            // Amount of allocation in xGrail
        bytes data;                // Bytes to send in the usageData field
    }

    address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
    address public constant camelotRouter = address(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

    bytes32 internal constant _YIELD_BOOSTER_SLOT = 0xbec2ddcc523ceccf38b524de8ba8b3f9263c108934a48e6c1382566b16a326d2;
    bytes32 internal constant _ALLOCATION_WHITELIST_SLOT = 0x0a5b0b20c401b06b37b537c3cab830e5993f53887001d5bcca3f1a84420b9ac4;

    CurrentAllocation[] public currentAllocations;
    TargetAllocation[] public allocationTargets;
    address[] public rewardTokens;
    mapping(address => bool) internal isLp;

    modifier onlyAllocationWhitelist() {
        require(_isAddressInList(msg.sender, allocationWhitelist()),
        "Caller has to be whitelisted");
        _;
    }

    constructor() public BaseUpgradeableStrategy() {
        assert(_YIELD_BOOSTER_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.yieldBooster")) - 1));
        assert(_ALLOCATION_WHITELIST_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.allocationWhitelist")) - 1));
    }

    function initializeBaseStrategy(
        address _storage,
        address _underlying,
        address _vault,
        address _grail,
        address _yieldBooster
    ) public initializer {

        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            IXGrail(_underlying).dividendsAddress(),
            _grail,
            harvestMSIG
        );

        setAddress(_YIELD_BOOSTER_SLOT, _yieldBooster);
        address[] memory whitelist = new address[](3);
        whitelist[0] = governance();
        whitelist[1] = harvestMSIG;
        whitelist[2] = address(0x6a74649aCFD7822ae8Fb78463a9f2192752E5Aa2);
        setAddressArray(_ALLOCATION_WHITELIST_SLOT, whitelist);
    }

    function yieldBooster() public view returns(address) {
        return getAddress(_YIELD_BOOSTER_SLOT);
    }

    function setYieldBooster(address _target) public onlyGovernance {
        setAddress(_YIELD_BOOSTER_SLOT, _target);
    }

    function allocationWhitelist() public view returns(address[] memory) {
        return getAddressArray(_ALLOCATION_WHITELIST_SLOT);
    }

    function setAllocationWhitelist(address[] memory _allocationWhitelist) public onlyGovernance {
        setAddressArray(_ALLOCATION_WHITELIST_SLOT, _allocationWhitelist);
    }

    function depositArbCheck() external pure returns(bool) {
        return true;
    }

    function dividendsAddress() public view returns(address) {
        return IXGrail(underlying()).dividendsAddress();
    }

    function _liquidateRewards(uint256 _xGrailAmount) internal {
        address _rewardToken = rewardToken();
        address _universalLiquidator = universalLiquidator();
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            if (isLp[token]) {
                address token0 = ICamelotPair(token).token0();
                address token1 = ICamelotPair(token).token1();
                IERC20(token).safeApprove(camelotRouter, 0);
                IERC20(token).safeApprove(camelotRouter, balance);
                ICamelotRouter(camelotRouter).removeLiquidity(token0, token1, balance, 1, 1, address(this), block.timestamp);
                uint256 balance0 = IERC20(token0).balanceOf(address(this));
                if (token0 != _rewardToken){
                    IERC20(token0).safeApprove(_universalLiquidator, 0);
                    IERC20(token0).safeApprove(_universalLiquidator, balance0);
                    IUniversalLiquidator(_universalLiquidator).swap(token0, _rewardToken, balance0, 1, address(this));
                }
                uint256 balance1 = IERC20(token1).balanceOf(address(this));
                if (token1 != _rewardToken){
                    IERC20(token1).safeApprove(_universalLiquidator, 0);
                    IERC20(token1).safeApprove(_universalLiquidator, balance1);
                    IUniversalLiquidator(_universalLiquidator).swap(token1, _rewardToken, balance1, 1, address(this));
                }
            } else {
                if (token != _rewardToken){
                    IERC20(token).safeApprove(_universalLiquidator, 0);
                    IERC20(token).safeApprove(_universalLiquidator, balance);
                    IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
                }
            }
        }

        uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
        if (rewardBalance < 1e12){
            return;
        }
        _notifyProfitInRewardToken(_rewardToken, rewardBalance.add(_xGrailAmount));
        uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

        if (remainingRewardBalance == 0) {
            return;
        }

        _depositGrail(remainingRewardBalance);
    }

    function _depositGrail(uint256 amount) internal {
        address _rewardToken = rewardToken();
        address _underlying = underlying();
        IERC20(_rewardToken).safeApprove(_underlying, 0);
        IERC20(_rewardToken).safeApprove(_underlying, amount);
        IXGrail(_underlying).convert(amount);
    }

    function getCurrentAllocation(address allocationAddress, bytes memory data) public view returns(uint256) {
        if (allocationAddress == dividendsAddress()) {
            return IXGrail(underlying()).getUsageAllocation(address(this), allocationAddress);
        } else if (allocationAddress == yieldBooster()) {
            (address poolAddress, uint256 tokenId) = abi.decode(data, (address, uint256));
            return IYieldBooster(yieldBooster()).getUserPositionAllocation(address(this), poolAddress, tokenId);
        }
    }

    function xGrailBalanceAllocated() view public returns (IXGrail.XGrailBalance memory) {
        return IXGrail(underlying()).getXGrailBalance(address(this));
    }

    function investedUnderlyingBalance() view public returns (uint256) {
        return xGrailBalanceAllocated().allocatedAmount.add(IERC20(underlying()).balanceOf(address(this)));
    }

    function doHardWork() external onlyNotPausedInvesting restricted {
        address _underlying = underlying();
        uint256 balanceBefore = IERC20(_underlying).balanceOf(address(this));
        IDividendsV2(dividendsAddress()).harvestAllDividends();
        uint256 claimedXGrail = IERC20(_underlying).balanceOf(address(this)).sub(balanceBefore);
        _liquidateRewards(claimedXGrail);
        rebalanceAllocations();
    }

    function rebalanceAllocations() public onlyNotPausedInvesting restricted {
        uint256 maxLength = currentAllocations.length.add(allocationTargets.length);
        address[] memory increaseAddresses = new address[](maxLength);
        uint256[] memory increaseAmounts = new uint256[](maxLength);
        bytes[] memory increaseDatas = new bytes[](maxLength);
        address[] memory decreaseAddresses = new address[](maxLength);
        uint256[] memory decreaseAmounts = new uint256[](maxLength);
        bytes[] memory decreaseDatas = new bytes[](maxLength);
        uint256 nDecrease = 0;
        uint256 nIncrease = 0;

        for (uint256 i; i < currentAllocations.length; i++) {  //Check if we have current allocations that are not in the targets
            address allocationAddress = currentAllocations[i].allocationAddress;
            bytes memory data = currentAllocations[i].data;
            bool isTarget = false;
            for (uint256 j; j < allocationTargets.length; j++) {
                address targetAddress = allocationTargets[j].allocationAddress;
                bytes memory targetData = allocationTargets[j].data;
                if (targetAddress == allocationAddress && keccak256(targetData) == keccak256(data)) {
                    isTarget = true;
                    break;
                }
            }
            if (!isTarget) {
                decreaseAddresses[nDecrease] = allocationAddress;
                decreaseAmounts[nDecrease] = currentAllocations[i].amount;
                decreaseDatas[nDecrease] = data;
                nDecrease += 1;
            }
        }

        uint256 nAllocations = 0;
        for (uint256 i; i < allocationTargets.length; i++) {           //Split target allocations into increases and decreases
            address allocationAddress = allocationTargets[i].allocationAddress;
            bytes memory data = allocationTargets[i].data;
            uint256 currentAmount = getCurrentAllocation(allocationAddress, data);
            uint256 targetAmount = investedUnderlyingBalance().mul(allocationTargets[i].weight).div(10000);
            if (currentAmount > targetAmount) {
                decreaseAddresses[nDecrease] = allocationAddress;
                decreaseAmounts[nDecrease] = currentAmount.sub(targetAmount);
                decreaseDatas[nDecrease] = data;
                nDecrease += 1;
            } else if (targetAmount > currentAmount) {
                increaseAddresses[nIncrease] = allocationAddress;
                increaseAmounts[nIncrease] = targetAmount.sub(currentAmount);
                increaseDatas[nIncrease] = data;
                nIncrease += 1;
            } else {    //No change in amount, store to current positions
                CurrentAllocation memory newAllocation;
                newAllocation.allocationAddress = allocationAddress;
                newAllocation.amount = targetAmount;
                newAllocation.data = data;
                if (nAllocations >= currentAllocations.length) {
                    currentAllocations.push(newAllocation);
                } else {
                    currentAllocations[nAllocations] = newAllocation;
                }
                nAllocations += 1;
            }
        }

        for (uint256 i; i < nDecrease; i++) {        //First handle decreases to free up xGrail for increases
            uint256 currentAllocation = getCurrentAllocation(decreaseAddresses[i], decreaseDatas[i]);
            if (currentAllocation > 0){
                IXGrail(underlying()).deallocate(decreaseAddresses[i], Math.min(decreaseAmounts[i], currentAllocation), decreaseDatas[i]);
                if (getCurrentAllocation(decreaseAddresses[i], decreaseDatas[i]) > 0){
                    CurrentAllocation memory newAllocation;
                    newAllocation.allocationAddress = decreaseAddresses[i];
                    newAllocation.amount = getCurrentAllocation(decreaseAddresses[i], decreaseDatas[i]);
                    newAllocation.data = decreaseDatas[i];
                    if (nAllocations >= currentAllocations.length) {
                        currentAllocations.push(newAllocation);
                    } else {
                        currentAllocations[nAllocations] = newAllocation;
                    }
                    nAllocations += 1;
                }
            }
        }

        for (uint256 i; i < nIncrease; i++) {        //Now handle increases
            address _underlying = underlying();
            uint256 _amount = Math.min(increaseAmounts[i], IERC20(_underlying).balanceOf(address(this)));
            IXGrail(_underlying).approveUsage(increaseAddresses[i], _amount);
            IXGrail(_underlying).allocate(increaseAddresses[i], _amount, increaseDatas[i]);
            CurrentAllocation memory newAllocation;
            newAllocation.allocationAddress = increaseAddresses[i];
            newAllocation.amount = getCurrentAllocation(increaseAddresses[i], increaseDatas[i]);
            newAllocation.data = increaseDatas[i];
            if (nAllocations >= currentAllocations.length) {
                currentAllocations.push(newAllocation);
            } else {
                currentAllocations[nAllocations] = newAllocation;
            }
            nAllocations += 1;
        }

        if (currentAllocations.length > nAllocations) {
            for (uint256 i; i < (currentAllocations.length).sub(nAllocations); i++) {
                currentAllocations.pop();
            }
        }
    }

    function setAllocationTargets(
        address[] memory addresses,
        uint256[] memory weights,
        address[] memory poolAddresses,
        uint256[] memory tokenIds
    ) external onlyAllocationWhitelist {
        require(addresses.length == weights.length, "Array mismatch");
        require(addresses.length == poolAddresses.length, "Array mismatch");
        require(addresses.length == tokenIds.length, "Array mismatch");
        uint256 totalWeight = 0;
        for (uint256 i; i < addresses.length; i++) {
            if (addresses[i] == dividendsAddress()) {
                require(weights[i] >= 5000, "Dividend weight");
            }
            TargetAllocation memory newAllocation;
            newAllocation.allocationAddress = addresses[i];
            newAllocation.weight = weights[i];
            if (addresses[i] == dividendsAddress()) {
                newAllocation.data = new bytes(0);
            } else {
                newAllocation.data = abi.encode(poolAddresses[i], tokenIds[i]);
            }
            if (i >= allocationTargets.length) {
                allocationTargets.push(newAllocation);
            } else {
                allocationTargets[i] = newAllocation;
            }
            totalWeight = totalWeight.add(weights[i]);
        }

        require(totalWeight == 10000, "Total weight");

        if (allocationTargets.length > addresses.length) {
            for (uint256 i; i < (allocationTargets.length).sub(addresses.length); i++) {
                allocationTargets.pop();
            }
        }
    }

    function _deallocateAll() internal {
        for (uint256 i; i < currentAllocations.length; i++) {
            if (getCurrentAllocation(currentAllocations[i].allocationAddress, currentAllocations[i].data) > 0) {
                IXGrail(underlying()).deallocate(
                    currentAllocations[i].allocationAddress,
                    getCurrentAllocation(currentAllocations[i].allocationAddress, currentAllocations[i].data),
                    currentAllocations[i].data
                );
            }
        }
        for (uint256 i; i < currentAllocations.length; i++) {
            currentAllocations.pop();
        }
    }

    function _deallocatePartial(uint256 amount) internal {
        uint256 balanceBefore = IERC20(underlying()).balanceOf(address(this));
        uint256 toDeallocate = amount;
        for (uint256 i; i < currentAllocations.length; i++) {
            IXGrail(underlying()).deallocate(
                currentAllocations[i].allocationAddress,
                Math.min(currentAllocations[i].amount, toDeallocate.mul(101).div(100)),
                currentAllocations[i].data
            );
            currentAllocations[i].amount = getCurrentAllocation(currentAllocations[i].allocationAddress, currentAllocations[i].data);

            uint256 balanceNew = IERC20(underlying()).balanceOf(address(this));
            uint256 balanceChange = balanceNew.sub(balanceBefore);
            balanceBefore = balanceNew;
            if (balanceChange >= toDeallocate) {
                return;
            } else {
                toDeallocate = toDeallocate.sub(balanceChange);
            }
        }
    }

    function withdrawAllToVault() public restricted {
        address _underlying = underlying();
        uint256 balanceBefore = IERC20(_underlying).balanceOf(address(this));
        IDividendsV2(dividendsAddress()).harvestAllDividends();
        uint256 claimedXGrail = IERC20(_underlying).balanceOf(address(this)).sub(balanceBefore);
        _deallocateAll();
        _liquidateRewards(claimedXGrail);
        IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }

    function withdrawToVault(uint256 _amount) public restricted {
        // Typically there wouldn't be any amount here
        // however, it is possible because of the emergencyExit
        address _underlying = underlying();
        uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));

        if(_amount > entireBalance){
            // While we have the check above, we still using SafeMath below
            // for the peace of mind (in case something gets changed in between)
            uint256 needToWithdraw = _amount.sub(entireBalance);
            uint256 toWithdraw = Math.min(xGrailBalanceAllocated().allocatedAmount, needToWithdraw);
            _deallocatePartial(toWithdraw);
        }
        IERC20(_underlying).safeTransfer(vault(), _amount);
        rebalanceAllocations();
    }

    function emergencyExit() public onlyGovernance {
        _deallocateAll();
        _setPausedInvesting(true);
    }

    function continueInvesting() public onlyGovernance {
        _setPausedInvesting(false);
    }


    function unsalvagableTokens(address token) public view returns (bool) {
        return (token == rewardToken() || token == underlying());
    }

    function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
        // To make sure that governance cannot come in and take away the coins
        require(!unsalvagableTokens(token), "token is defined as not salvagable");
        IERC20(token).safeTransfer(recipient, amount);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }
}
