/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Object for tracking a dated irs position
 * todo: annualization logic might fit nicely in here + any other irs position specific helpers
 */
library Position {
    struct Data {
        int256 baseBalance;
        int256 quoteBalance;
    }

    function update(Data storage self, int256 baseDelta, int256 quoteDelta) internal {
        self.baseBalance += baseDelta;
        self.quoteBalance += quoteDelta;
    }
}

