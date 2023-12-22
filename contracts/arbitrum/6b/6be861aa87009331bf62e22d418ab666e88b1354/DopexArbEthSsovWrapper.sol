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
import {SafeMath} from "./SafeMath.sol";
import {IERC20} from "./IERC20.sol";
import {IArbEthSSOVV2} from "./IArbEthSSOVV2.sol";

library DopexArbEthSsovWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ============================== Dopex Arb Ssov wrapper interaction ==============================

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of ETH to deposit.
     * @return Whether deposit was successful.
     */
    function depositSSOV(
        IArbEthSSOVV2 self,
        uint256 _strikeIndex,
        uint256 _amount,
        address _caller
    ) public returns (bool) {
        self.deposit{value: _amount}(_strikeIndex, _caller);
        emit SSOVDeposit(self.currentEpoch(), _strikeIndex, _amount);
        return true;
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of ETH to deposit.
     * @return Whether deposits went through successfully.
     */
    function depositSSOVMultiple(
        IArbEthSSOVV2 self,
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts,
        address _caller
    ) public returns (bool) {
        uint256 totalAmount;
        require(
            _strikeIndices.length == _amounts.length,
            "Arguments Lenght do not match"
        );
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount = totalAmount.add(_amounts[i]);
        }

        self.depositMultiple{value: totalAmount}(
            _strikeIndices,
            _amounts,
            _caller
        );

        for (uint256 i = 0; i < _amounts.length; i++) {
            emit SSOVDeposit(
                self.currentEpoch(),
                _strikeIndices[i],
                _amounts[i]
            );
        }

        return true;
    }

    /**
     * Buys calls from Dopex SSOV.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of calls to purchase.
     * @param _price Amount of ETH we are willing to pay for these calls.
     * @return Whether call purchase went through successfully.
     */
    function purchaseCall(
        IArbEthSSOVV2 self,
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _price,
        address _caller
    ) public returns (bool) {
        (uint256 premium, uint256 totalFee) = self.purchase{value: _price}(
            _strikeIndex,
            _amount,
            _caller
        );
        emit SSOVCallPurchase(
            self.currentEpoch(),
            _strikeIndex,
            _amount,
            premium,
            totalFee
        );
        return true;
    }

    /**
     * Claims deposits and settle calls from Dopex SSOV at the end of an epoch.
     * @param _caller the address seleting the epoch
     * @return Whether settling was successful.
     */
    function settleEpoch(IArbEthSSOVV2 self, address _caller)
        public
        returns (bool)
    {
        uint256 epoch = self.currentEpoch();

        // calls
        address[] memory strikeTokens = self.getEpochStrikeTokens(epoch);
        for (uint256 i = 0; i < strikeTokens.length; i++) {
            IERC20 strikeToken = IERC20(strikeTokens[i]);
            uint256 strikeTokenBalance = strikeToken.balanceOf(_caller);
            if (strikeTokenBalance > 0) {
                strikeToken.safeApprove(address(self), strikeTokenBalance);
                self.settle(i, strikeTokenBalance, epoch);
            }
        }

        // deposits
        uint256[] memory vaultDeposits = self.getUserEpochDeposits(
            epoch,
            _caller
        );
        for (uint256 i = 0; i < vaultDeposits.length; i++) {
            if (vaultDeposits[i] > 0) {
                self.withdraw(epoch, i);
            }
        }

        return true;
    }

    // ============================== Events ==============================

    /**
     * emitted when new Deposit to SSOV is made
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount deposit amount
     */
    event SSOVDeposit(
        uint256 indexed _epoch,
        uint256 _strikeIndex,
        uint256 _amount
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
        uint256 _totalFee
    );
}

