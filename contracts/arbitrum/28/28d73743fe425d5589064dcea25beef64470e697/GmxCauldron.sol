// SPDX-License-Identifier: UNLICENSED

// Cauldron

//    (                (   (
//    )\      )    (   )\  )\ )  (
//  (((_)  ( /(   ))\ ((_)(()/(  )(    (    (
//  )\___  )(_)) /((_) _   ((_))(()\   )\   )\ )
// ((/ __|((_)_ (_))( | |  _| |  ((_) ((_) _(_/(
//  | (__ / _` || || || |/ _` | | '_|/ _ \| ' \))
//   \___|\__,_| \_,_||_|\__,_| |_|  \___/|_||_|

pragma solidity >=0.8.0;
import "./CauldronV4.sol";
import "./GmxLib.sol";

// solhint-disable avoid-low-level-calls
// solhint-disable no-inline-assembly

/// @title Cauldron
/// @dev This contract allows contract calls to any contract (except BentoBox)
/// from arbitrary callers thus, don't trust calls from this contract in any circumstances.
contract GmxCauldron is CauldronV4 {
    address public immutable rewardRouter;
    address public immutable baseContract;
    uint256 public rewardPershare;
    mapping(address => uint256) public userRwardDebt;
    // uint256 public constant PRECISION = 1e20;
    bool public isGLP = false;

    error InsufficientStakeBalance();

    constructor(
        IBentoBoxV1 bentoBox_,
        IERC20 magicInternetMoney_,
        address distributeTo_,
        address _arvinDegenNftAddress,
        address _rewardRouter,
        address _baseContract
    ) CauldronV4(bentoBox_, magicInternetMoney_, distributeTo_, _arvinDegenNftAddress) {
        rewardRouter = _rewardRouter;
        baseContract = _baseContract;
        blacklistedCallees[_rewardRouter] = true;
        blacklistedCallees[address(collateral)] = true;
    }

    function init(bytes memory data) public payable virtual override {
        (bytes memory actualData, bool _isGLP) = abi.decode(data, (bytes, bool));
        // super.init(actualData);
        //bytecode optimize
        address(baseContract).delegatecall(abi.encodeWithSelector(IMasterContract.init.selector, actualData));
        blacklistedCallees[address(rewardRouter)] = true;
        collateral.approve(address(bentoBox), type(uint256).max);
        (address stakedTracker, address feeTracker) = GmxLib.getTrackers(rewardRouter, _isGLP);
        if (_isGLP) {
            blacklistedCallees[address(collateral)] = true;
        } else {
            collateral.approve(stakedTracker, type(uint256).max);
        }
        blacklistedCallees[stakedTracker] = true;
        isGLP = _isGLP;
    }

    function _beforeAddCollateral(address user, uint256) internal virtual override {
        _harvest(user);
    }

    function _beforeRemoveCollateral(address from, address, uint256 collateralShare) internal virtual override {
        _harvest(from);
    }

    function _afterAddCollateral(address user, uint256 collateralShare) internal virtual override {
        _stake(user, collateralShare);
        _updateUserDebt(user);
    }

    function _afterRemoveCollateral(address from, address, uint256 collateralShare) internal virtual override {
        _unstake(collateralShare);
        _updateUserDebt(from);
    }

    function _beforeUserLiquidated(address user, uint256, uint256, uint256 collateralShare) internal virtual override {
        _harvest(user);
        _unstake(collateralShare);
    }

    function _afterUserLiquidated(address user, uint256 collateralShare) internal virtual override {
        _updateUserDebt(user);
    }

    function pendingReward(address user) external view returns (uint256) {
        (, address feeTracker) = GmxLib.getTrackers(rewardRouter, isGLP);
        uint256 pending = GmxLib.getClaimable(feeTracker, address(this));
        uint256 rpc = rewardPershare;
        if (pending > 0) {
            rpc += (pending * 1e20) / totalCollateralShare;
        }
        return (userCollateralShare[user] * rpc) / 1e20 - userRwardDebt[user];
    }

    function claim() external {
        address user = msg.sender;
        uint256 ucs = userCollateralShare[user];
        if (ucs == 0) return;
        _harvest(user);
        _updateUserDebt(user);
    }

    function _updateUserDebt(address user) private {
        userRwardDebt[user] = (userCollateralShare[user] * rewardPershare) / 1e20;
    }

    function _stake(address user, uint256 collateralShare) private {
        GmxLib.stake(bentoBox, collateral, rewardRouter, collateralShare, isGLP);
    }

    function _unstake(uint256 collateralShare) private {
        GmxLib.unstake(bentoBox, collateral, rewardRouter, collateralShare, isGLP);
    }

    function _harvest(address user) private {
        rewardPershare = GmxLib.harvest(
            rewardRouter,
            user,
            userCollateralShare[user],
            userRwardDebt[user],
            rewardPershare,
            totalCollateralShare
        );
    }

    receive() external payable {}
}

