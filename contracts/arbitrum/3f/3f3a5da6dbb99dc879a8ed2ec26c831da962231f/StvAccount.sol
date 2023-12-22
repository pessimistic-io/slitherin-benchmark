// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Errors} from "./Errors.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IVault} from "./IVault.sol";
import {IOperator} from "./IOperator.sol";

/// @title StvAccount
/// @notice Contract which is cloned and deployed for every stv created by a `manager` through `Vault` contract
contract StvAccount {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice address of the operator contract
    address private immutable OPERATOR;
    /// @notice info of the stv 
    IVault.StvInfo public stvInfo;
    /// @notice balances of the stv
    IVault.StvBalance public stvBalance;
    /// @notice info of the investors who deposited into the stv
    mapping(address => IVault.InvestorInfo) public investorInfo;
    /// @notice array of investors
    address[] public investors;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR/MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _operator) {
        OPERATOR = _operator;
    }

    modifier onlyVault() {
        address vault = IOperator(OPERATOR).getAddress("VAULT");
        if (msg.sender != vault) revert Errors.NoAccess();
        _;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice function to execute trades on different ddexes
    /// @dev can only be called by a plugin
    /// @param adapter address of the contract
    /// @param data calldata
    function execute(address adapter, bytes calldata data) external payable returns (bytes memory) {
        bool isPlugin = IOperator(OPERATOR).getPlugin(msg.sender);
        if (!isPlugin) revert Errors.NoAccess();
        (bool success, bytes memory returnData) = adapter.call{value: msg.value}(data);
        if (!success) revert Errors.CallFailed(returnData);
        return returnData;
    }

    /// @notice updates the state `stvInfo`
    /// @dev can only be called by the `Vault` contract
    /// @param stv StvInfo
    function createStv(IVault.StvInfo memory stv) external onlyVault {
        stvInfo = stv;
    }

    /// @notice updates `totalRaised` and the `investorInfo`
    /// @dev can only be called by the `Vault` contract
    /// @param investorAccount address of the investor's Account contract
    /// @param amount amount deposited into the stv
    /// @param isFirstDeposit bool to check if its the first time deposit by the investor
    function deposit(address investorAccount, uint96 amount, bool isFirstDeposit) external onlyVault {
        if (isFirstDeposit) investors.push(investorAccount);
        stvBalance.totalRaised += amount;
        investorInfo[investorAccount].depositAmount += amount;
    }

    /// @notice updates `status` of the stv
    /// @dev can only be called by the `Vault` contract
    function liquidate() external onlyVault {
        stvInfo.status = IVault.StvStatus.LIQUIDATED;
    }

    /// @notice updates state according to increase or decrease trade
    /// @dev can only be called by the `Vault` contract
    /// @param amount amount of tokens used to increase/decrease position
    /// @param totalReceived tokens received after the position is executed
    /// @param isOpen bool to check if its an increase or a decrease trade
    function execute(uint96 amount, uint96 totalReceived, bool isOpen) external onlyVault {
        if (isOpen) {
            stvInfo.status = IVault.StvStatus.OPEN;
            stvBalance.totalDepositTokenUsedForOpen += amount;
            stvBalance.totalReceivedAfterOpen += totalReceived;
        } else {
            stvBalance.totalTradeTokenUsedForClose += amount;
            stvBalance.totalReceivedAfterClose += totalReceived;
        }
    }

    /// @notice transfers all the tokens to the respective investors
    /// @dev can only be called by the `Vault` contract
    /// @param totalRemainingAfterDistribute amount of tokens remaining after the stv is closed
    /// @param mFee manager fees
    /// @param pFee performance fees
    function distribute(uint96 totalRemainingAfterDistribute, uint96 mFee, uint96 pFee) external onlyVault {
        stvInfo.status = IVault.StvStatus.DISTRIBUTED;
        stvBalance.totalRemainingAfterDistribute = totalRemainingAfterDistribute;

        if (mFee > 0 || pFee > 0) {
            IVault.StvInfo memory stv = stvInfo;
            address managerAccount = IOperator(OPERATOR).getTraderAccount(stv.manager);
            address treasury = IOperator(OPERATOR).getAddress("TREASURY");
            IERC20(stv.depositToken).safeTransfer(managerAccount, mFee);
            IERC20(stv.depositToken).safeTransfer(treasury, pFee);
        }

        _distribute(false, 0, investors.length);
    }

    /// @notice called if `distribute` runs out of gas
    /// @dev can only be called by the `Vault` contract
    /// @param isCancel bool to check if the stv is cancelled or closed
    /// @param indexFrom starting index to transfer the tokens to the investors
    /// @param indexTo ending index to transfer the tokens to the investors
    function distributeOut(bool isCancel, uint256 indexFrom, uint256 indexTo) external onlyVault {
        _distribute(isCancel, indexFrom, indexTo);
    }

    /// @notice updates `status` of the stv
    /// @dev can only be called by the `Vault` contract
    /// @param status status of the stv
    function updateStatus(IVault.StvStatus status) external onlyVault {
        stvInfo.status = status;
    }

    /// @notice cancels the stv and transfers the tokens back to the investors
    /// @dev can only be called by the `Vault` contract
    function cancel() external onlyVault {
        stvInfo.endTime = 0;
        _distribute(true, 0, investors.length);
    }

    /// @notice get the claimableAmount after the stv is closed
    /// @dev can only be called by the `Vault` contract
    /// @param investorAccount address of the investor's Account contract
    function getClaimableAmountAfterDistribute(address investorAccount) public view returns (uint96 claimableAmount) {
        return _getClaimableAmountAfterDistribute(investorAccount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getClaimableAmountAfterDistribute(address investorAccount)
        internal
        view
        returns (uint96 claimableAmount)
    {
        IVault.InvestorInfo memory _investorInfo = investorInfo[investorAccount];
        IVault.StvBalance memory _stvBalance = stvBalance;

        if (stvInfo.status == IVault.StvStatus.DISTRIBUTED && !_investorInfo.claimed) {
            claimableAmount =
                (_stvBalance.totalRemainingAfterDistribute * _investorInfo.depositAmount) / _stvBalance.totalRaised;
        } else {
            claimableAmount = 0;
        }
    }

    function _distribute(bool isCancel, uint256 indexFrom, uint256 indexTo) internal {
        address[] memory _investors = investors;
        address defaultStableCoin = IOperator(OPERATOR).getAddress("DEFAULTSTABLECOIN");
        uint256 i = indexFrom;

        if (isCancel) {
            for (; i < indexTo;) {
                address investorAccount = _investors[i];
                IVault.InvestorInfo memory _investorInfo = investorInfo[investorAccount];
                IERC20(defaultStableCoin).safeTransfer(investorAccount, _investorInfo.depositAmount);
                unchecked {
                    ++i;
                }
            }
        } else {
            for (; i < indexTo;) {
                address investorAccount = _investors[i];
                uint96 claimableAmount = _getClaimableAmountAfterDistribute(investorAccount);
                if (investorInfo[investorAccount].claimed) continue;

                investorInfo[investorAccount].claimed = true;
                investorInfo[investorAccount].claimedAmount = claimableAmount;
                IERC20(defaultStableCoin).safeTransfer(investorAccount, claimableAmount);
                unchecked {
                    ++i;
                }
            }
        }
    }
}

