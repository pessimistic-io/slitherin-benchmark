// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAssetManager} from "./IAssetManager.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";
import {ILiquidator} from "./ILiquidator.sol";

import "./AccessControl.sol";
import "./EnumerableSet.sol";
import "./IERC20Metadata.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Liquidator: checks for accounts to be liquidated from the BalanceSheet
///                    and executes the liquidation on AssetManager
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Liquidator is ILiquidator, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    address public immutable assetManagerAddress;
    address public immutable balanceSheetAddress;
    address public immutable usdcAddress;

    event AddedToLiquidationCandidates(address _account);
    event AddedToReadyForLiquidationCandidates(address _account);
    event RemovedFromLiquidationCandidates(address _account);
    event RemovedFromReadyForLiquidationCandidates(address _account);
    event CandidateLiquidated(address _account);
    event WithdrewERC20(
        address _operator,
        address _to,
        uint256 _amount,
        address _tokenAddress
    );

    EnumerableSet.AddressSet private liquidationCandidates; // 1st time offenders - given a chance to improve health score
    EnumerableSet.AddressSet private readyForLiquidationCandidates; // 2nd time offenders - will be liquidated

    constructor(
        address _assetManagerAddress,
        address _balanceSheetAddress,
        address _usdcAddress
    ) {
        assetManagerAddress = _assetManagerAddress;
        balanceSheetAddress = _balanceSheetAddress;
        usdcAddress = _usdcAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice calls BalanceSheet to get a list of accounts to be liquidated
     *         and adds them to the liquidationCandidates set
     *         or readyForLiquidationCandidates set if they are already in the liquidationCandidates set
     * @dev only callable by the admin
     */
    function setLiquidationCandidates() public onlyAdmin {
        address[] memory liquidatables = IBalanceSheet(balanceSheetAddress)
            .getLiquidatables();

        // no liquidatable accounts
        // reset the existing liquidation candidates
        // we can't just reset the EnumerableSet
        // because it will corrupt the storage https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableSet
        // we have to iterate through the existing set and remove each element
        if (liquidatables.length == 0) {
            address[] memory existingCandidates = EnumerableSet.values(
                liquidationCandidates
            );
            for (uint256 i = 0; i < existingCandidates.length; i++) {
                liquidationCandidates.remove(existingCandidates[i]);

                emit RemovedFromLiquidationCandidates(existingCandidates[i]);
            }
        } else {
            // there are liquidatable accounts
            for (uint256 i = 0; i < liquidatables.length; i++) {
                // if the account is already in the liquidationCandidates set
                // then we need to remove it from the set
                // and add it to the readyForLiquidationCandidates set
                if (
                    EnumerableSet.contains(
                        liquidationCandidates,
                        liquidatables[i]
                    )
                ) {
                    EnumerableSet.remove(
                        liquidationCandidates,
                        liquidatables[i]
                    );

                    emit RemovedFromLiquidationCandidates(liquidatables[i]);

                    EnumerableSet.add(
                        readyForLiquidationCandidates,
                        liquidatables[i]
                    );

                    emit AddedToReadyForLiquidationCandidates(liquidatables[i]);
                } else {
                    // if the account is not in the liquidationCandidates set
                    // then we need to add it to the set
                    liquidationCandidates.add(liquidatables[i]);

                    emit AddedToLiquidationCandidates(liquidatables[i]);
                }
            }
        }
    }

    /**
     * @notice iterates through the readyForLiquidationCandidates set and calls on Asset Manager to liquidate
     * @dev only callable by the admin
     */
    function executeLiquidations() public onlyAdmin {
        address[] memory candidates = EnumerableSet.values(
            readyForLiquidationCandidates
        );
        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 owedAmount = IBalanceSheet(balanceSheetAddress)
                .getOutstandingLoan(candidates[i]);
            IERC20Metadata(usdcAddress).approve(
                assetManagerAddress,
                _amountInUSDC(owedAmount)
            );

            IAssetManager(assetManagerAddress).makePayment(
                owedAmount,
                candidates[i]
            );
            IAssetManager(assetManagerAddress).liquidate(candidates[i]);
            emit CandidateLiquidated(candidates[i]);

            // remove the account from the readyForLiquidationCandidates set
            EnumerableSet.remove(readyForLiquidationCandidates, candidates[i]);
            emit RemovedFromReadyForLiquidationCandidates(candidates[i]);
        }
    }

    /**
     * @notice returns the list of liquidation candidates
     * @return the list of liquidatable accounts
     */
    function getLiquidatableCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSet.values(liquidationCandidates);
    }

    /**
     * @notice returns the list of ready for liquidation candidates
     * @return the list of ready for liquidation candidates
     */
    function getReadyForLiquidationCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSet.values(readyForLiquidationCandidates);
    }

    /**
     * @notice withdraw erc20
     * @param _to - address
     * @param _amount - amount
     * @param _tokenAddress - token address
     */
    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) public onlyAdmin {
        IERC20(_tokenAddress).transfer(_to, _amount);
        emit WithdrewERC20(msg.sender, _to, _amount, _tokenAddress);
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Liquidator: only DefragSystemAdmin"
        );
        _;
    }

    /**
     * @notice helper to convert wei into USDC
     * @param _amount - 18 decimal amount
     * @return uint256 - USDC decimal compliant amount
     */
    function _amountInUSDC(uint256 _amount) internal view returns (uint256) {
        // because USDC is 6 decimals, we need to fix the decimals
        // https://docs.openzeppelin.com/contracts/4.x/erc20#a-note-on-decimals
        uint8 decimals = IERC20Metadata(usdcAddress).decimals();
        return (_amount / 10 ** (18 - decimals));
    }
}

