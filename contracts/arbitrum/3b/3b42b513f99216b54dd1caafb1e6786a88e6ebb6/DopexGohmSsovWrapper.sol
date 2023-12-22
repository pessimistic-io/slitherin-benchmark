// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   *********************  
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/

pragma solidity ^0.8.2;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IGohmSSOVV2} from "./IGohmSSOVV2.sol";

library DopexGohmSsovWrapper {
    using SafeERC20 for IERC20;

    address constant TOKEN = 0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1;

    // ============================== Dopex Arb Ssov wrapper interaction ==============================

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of token to deposit.
     * @param _depositor The depositor contract
     * @return Whether deposit was successful.
     */
    function depositSSOV(
        IGohmSSOVV2 self,
        uint256 _strikeIndex,
        uint256 _amount,
        address _depositor
    ) public returns (bool) {
        self.deposit(_strikeIndex, _amount, _depositor);
        emit SSOVDeposit(self.currentEpoch(), _strikeIndex, _amount, TOKEN);
        return true;
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of ETH to deposit.
     * @param _depositor The depositor contract
     * @return Whether deposits went through successfully.
     */
    function depositSSOVMultiple(
        IGohmSSOVV2 self,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _depositor
    ) public returns (bool) {
        require(
            _strikeIndices.length == _amounts.length,
            "Arguments Lenght do not match"
        );

        self.depositMultiple(_strikeIndices, _amounts, _depositor);

        for (uint256 i = 0; i < _amounts.length; i++) {
            emit SSOVDeposit(
                self.currentEpoch(),
                _strikeIndices[i],
                _amounts[i],
                TOKEN
            );
        }

        return true;
    }

    /**
     * Buys calls from Dopex SSOV.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of calls to purchase.
     * @param _buyer call buyer
     * @return Whether call purchase went through successfully.
     */
    function purchaseCall(
        IGohmSSOVV2 self,
        uint256 _strikeIndex,
        uint256 _amount,
        address _buyer
    ) public returns (bool) {
        (uint256 premium, uint256 totalFee) = self.purchase(
            _strikeIndex,
            _amount,
            _buyer
        );
        emit SSOVCallPurchase(
            self.currentEpoch(),
            _strikeIndex,
            _amount,
            premium,
            totalFee,
            TOKEN
        );
        return true;
    }

    /**
     * Claims deposits and settle calls from Dopex SSOV at the end of an epoch.
     * @param _caller the address seleting the epoch
     * @param _epoch the epoch to settle
     * @param _strikes the strikes to settle
     * @return Whether settling was successful.
     */
    function settleEpoch(
        IGohmSSOVV2 self,
        address _caller,
        uint256 _epoch,
        uint256[] memory _strikes
    ) public returns (bool) {
        if (_strikes.length == 0) {
            return false;
        }

        uint256 price = self.settlementPrices(_epoch);

        // calls
        address[] memory strikeTokens = self.getEpochStrikeTokens(_epoch);
        for (uint256 i = 0; i < _strikes.length; i++) {
            uint256 index = _strikes[i];
            IERC20 strikeToken = IERC20(strikeTokens[index]);
            uint256 strikeTokenBalance = strikeToken.balanceOf(_caller);
            uint256 strikePrice = self.epochStrikes(_epoch, index);
            uint256 pnl = self.calculatePnl(
                price,
                strikePrice,
                strikeTokenBalance
            );

            if (strikeTokenBalance > 0 && pnl > 0) {
                strikeToken.safeApprove(address(self), strikeTokenBalance);
                self.settle(index, strikeTokenBalance, _epoch);
            }
        }

        // deposits
        uint256[] memory vaultDeposits = self.getUserEpochDeposits(
            _epoch,
            _caller
        );
        for (uint256 i = 0; i < vaultDeposits.length; i++) {
            if (vaultDeposits[i] > 0) {
                self.withdraw(_epoch, i);
            }
        }

        return true;
    }

    /**
     * Allows withdraw of ssov deposits, mostly used in case of any emergency.
     * @param _strikeIndexes strikes to withdraw from
     * @param _epoch epoch to withdraw
     */
    function withdrawEpoch(
        IGohmSSOVV2 self,
        uint256[] memory _strikeIndexes,
        uint256 _epoch
    ) public {
        for (uint256 i = 0; i < _strikeIndexes.length; i++) {
            self.withdraw(_epoch, _strikeIndexes[i]);
        }
    }

    // ============================== Events ==============================

    /**
     * Emitted when new Deposit to SSOV is made
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount deposit amount
     */
    event SSOVDeposit(
        uint256 indexed _epoch,
        uint256 _strikeIndex,
        uint256 _amount,
        address _token
    );

    /**
     * emitted when new call from SSOV is purchased
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount call amount
     * @param _premium call premium
     * @param _totalFee call total fee
     */
    event SSOVCallPurchase(
        uint256 indexed _epoch,
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _premium,
        uint256 _totalFee,
        address _token
    );
}

