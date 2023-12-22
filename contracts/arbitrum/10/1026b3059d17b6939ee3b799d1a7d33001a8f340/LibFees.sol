//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibStorage.sol";
import "./SwapTypes.sol";
import "./IDXBL.sol";

library LibFees {

    /**
     * Compute gas fee in fee-token units. This uses the RevshareVault's access to oracles
     * to determing native gas price relative to fee token price.
     */
    function computeGasFee(SwapTypes.SwapRequest memory request, uint gasTotal) public view returns (uint gasFee) {
        LibDexible.DexibleStorage storage ds = LibStorage.getDexibleStorage();
        IRevshareVault vault = IRevshareVault(ds.revshareManager);
        return vault.convertGasToFeeToken(address(request.executionRequest.fee.feeToken), gasTotal);
    }

    /**
     * Compute the bps to charge for the swap. This leverages the DXBL token to compute discounts
     * based on trader balances and discount rates applied per DXBL token.
     */
    function computeBpsFee(SwapTypes.SwapRequest memory request, bool feeIsInput, uint preDXBL, uint outAmount) public view returns (uint) {
        //apply any discounts
        LibDexible.DexibleStorage storage ds = LibStorage.getDexibleStorage();
        
        return ds.dxblToken.computeDiscountedFee(
            IDXBL.FeeRequest({
                trader: request.executionRequest.requester,
                amt: feeIsInput ? request.tokenIn.amount : outAmount,
                referred: request.executionRequest.fee.affiliate != address(0),
                dxblBalance: preDXBL,
                stdBpsRate: ds.stdBpsRate,
                minBpsRate: ds.minBpsRate
            }));
    }

    function computeMinFeeUnits(address feeToken) public view returns (uint) {
        LibDexible.DexibleStorage storage rs = LibStorage.getDexibleStorage();
        if(rs.minFeeUSD == 0) {
            return 0;
        }

        IRevshareVault vault = IRevshareVault(rs.revshareManager);
        //fee token price is in 30-dec units.
        uint usdPrice = vault.feeTokenPriceUSD(feeToken);

        uint8 ftDecs = IERC20Metadata(feeToken).decimals();

        //fee USD configuration is expressed in 18-decimals. Have to convert to fee-token units and 
        //account for price units
        uint minFeeUSD = (rs.minFeeUSD * (ftDecs != 18 ? ((10**ftDecs) / 1e18) : 1)) * LibConstants.PRICE_PRECISION;

        //then simply divide to get fee token units that equate to min fee USD
        return  minFeeUSD / usdPrice;
    }
}
