//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {ISsovV3} from "./ISsovV3.sol";
import {ISsovV3Viewer} from "./ISsovV3Viewer.sol";
import {SafeERC20} from "./SafeERC20.sol";

library SsovAdapter {
    using SafeERC20 for IERC20;

    ISsovV3Viewer constant viewer = ISsovV3Viewer(0x9abE93F7A70998f1836C2Ee0E21988Ca87072001);

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of Collateral to deposit.
     * @param _depositor The depositor contract
     * @return tokenId tokenId of the deposit.
     */
    function depositSSOV(ISsovV3 self, uint256 _strikeIndex, uint256 _amount, address _depositor)
        public
        returns (uint256 tokenId)
    {
        tokenId = self.deposit(_strikeIndex, _amount, _depositor);
        uint256 epoch = self.currentEpoch();
        emit SSOVDeposit(epoch, _strikeIndex, _amount, tokenId);
    }

    /**
     * Purchase Dopex option.
     * @param self Dopex SSOV contract.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of options to purchase.
     * @param _buyer Jones strategy contract.
     * @return Whether deposit was successful.
     */
    function purchaseOption(ISsovV3 self, uint256 _strikeIndex, uint256 _amount, address _buyer)
        public
        returns (bool)
    {
        (uint256 premium, uint256 totalFee) = self.purchase(_strikeIndex, _amount, _buyer);

        emit SSOVPurchase(
            self.currentEpoch(), _strikeIndex, _amount, premium, totalFee, address(self.collateralToken())
            );

        return true;
    }

    function _settleEpoch(
        ISsovV3 self,
        uint256 _epoch,
        IERC20 _strikeToken,
        address _caller,
        uint256 _strikePrice,
        uint256 _settlementPrice,
        uint256 _strikeIndex,
        uint256 _settlementCollateralExchangeRate
    )
        private
    {
        uint256 strikeTokenBalance = _strikeToken.balanceOf(_caller);
        uint256 pnl =
            self.calculatePnl(_settlementPrice, _strikePrice, strikeTokenBalance, _settlementCollateralExchangeRate);
        if (strikeTokenBalance > 0 && pnl > 0) {
            _strikeToken.safeApprove(address(self), strikeTokenBalance);
            self.settle(_strikeIndex, strikeTokenBalance, _epoch, _caller);
        }
    }

    /**
     * Settles options from Dopex SSOV at the end of an epoch.
     * @param _caller the address settling the epoch
     * @param _epoch the epoch to settle
     * @param _strikes the strikes to settle
     * Returns bool to indicate if epoch settlement was successful.
     */
    function settleEpoch(ISsovV3 self, address _caller, uint256 _epoch, uint256[] memory _strikes)
        public
        returns (bool)
    {
        if (_strikes.length == 0) {
            return false;
        }

        ISsovV3.EpochData memory epochData = self.getEpochData(_epoch);
        uint256[] memory epochStrikes = epochData.strikes;
        uint256 price = epochData.settlementPrice;

        address[] memory strikeTokens = viewer.getEpochStrikeTokens(_epoch, self);
        for (uint256 i = 0; i < _strikes.length; i++) {
            uint256 index = _strikes[i];
            IERC20 strikeToken = IERC20(strikeTokens[index]);
            uint256 strikePrice = epochStrikes[index];
            _settleEpoch(
                self, _epoch, strikeToken, _caller, strikePrice, price, index, epochData.settlementCollateralExchangeRate
            );
        }
        return true;
    }

    function settleAllStrikesOnEpoch(ISsovV3 self, uint256 _epoch) public {
        ISsovV3.EpochData memory epochData = self.getEpochData(_epoch);
        uint256[] memory strikes = epochData.strikes;
        address[] memory strikeTokens = viewer.getEpochStrikeTokens(_epoch, self);

        for (uint256 i; i < strikes.length; i++) {
            _settleEpoch(
                self,
                _epoch,
                IERC20(strikeTokens[i]),
                address(this),
                strikes[i],
                epochData.settlementPrice,
                i,
                epochData.settlementCollateralExchangeRate
            );
        }
    }

    /**
     * Allows withdraw of all erc721 tokens ssov deposit for the given epoch and strikes.
     */
    function withdrawEpoch(ISsovV3 self, uint256 _epoch, uint256[] memory _strikes, address _caller) public {
        uint256[] memory tokenIds = viewer.walletOfOwner(_caller, self);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint256 epoch, uint256 strike,,,) = self.writePosition(tokenIds[i]);
            if (epoch == _epoch) {
                for (uint256 j = 0; j < _strikes.length; j++) {
                    if (strike == _strikes[j]) {
                        self.withdraw(tokenIds[i], _caller);
                    }
                }
            }
        }
    }

    /**
     * Emitted when new Deposit to SSOV is made
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount deposited Collateral Token amount
     * @param _tokenId token ID of the deposit
     */
    event SSOVDeposit(uint256 indexed _epoch, uint256 _strikeIndex, uint256 _amount, uint256 _tokenId);

    /**
     * emitted when new put/call from SSOV is purchased
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount put amount
     * @param _premium put/call premium
     * @param _totalFee put/call total fee
     */
    event SSOVPurchase(
        uint256 indexed _epoch,
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _premium,
        uint256 _totalFee,
        address _token
    );
}

