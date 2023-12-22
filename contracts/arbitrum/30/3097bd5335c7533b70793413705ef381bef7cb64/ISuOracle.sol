// SPDX-License-Identifier: UNLICENSED

// solhint-disable compiler-version
pragma solidity >=0.7.6;

interface ISuOracle {
    /**
     * @notice WARNING! Read this description very carefully!
     *     function getFiatPrice1e18(address asset) returns (uint256) that:
     *         basicAmountOfAsset * getFiatPrice1e18(asset) / 1e18 === $$ * 1e18
     *     in other words, it doesn't matter what's the erc20.decimals is,
     *     you just multiply token balance in basic units on value from oracle and get dollar amount multiplied on 1e18.
     *
     * different assets have different deviation threshold (errors)
     *     for wBTC it's <= 0.5%, read more https://data.chain.link/ethereum/mainnet/crypto-usd/btc-usd
     *     for other asset is can be larger based on particular oracle implementation.
     *
     * examples:
     *     market price of btc = $30k,
     *     for 0.1 wBTC the unit256 amount is 0.1 * 1e18
     *     0.1 * 1e18 * (price1e18 / 1e18) == $3000 == uint256(3000*1e18)
     *     => price1e18 = 30000 * 1e18;
     *
     *     market price of usdt = $0.97,
     *     for 1 usdt uint256 = 1 * 1e6
     *     so 1*1e6 * price1e18 / 1e18 == $0.97 == uint256(0.97*1e18)
     *     => 1*1e6 * (price1e18 / 1e18) / (0.97*1e18)   = 1
     *     =>  price1e18 = 0.97 * (1e18/1e6) * 1e18
     *
     *    assume market price of wBTC = $31,503.77, oracle error = $158
     *
     *     case #1: small amount of wBTC
     *         we have 0.0,000,001 wBTC that is worth v = $0.00315 ± $0.00001 = 0.00315*1e18 = 315*1e13 ± 1*1e13
     *         actual balance on the asset b = wBTC.balanceOf() =  0.0000001*1e18 = 1e11
     *         oracle should return or = oracle.getFiatPrice1e18(wBTC) <=>
     *         <=> b*or = v => v/b = 315*1e13 / 1e11 = 315*1e2 ± 1e2
     *         error = or.error * b = 1e2 * 1e11 = 1e13 => 1e13/1e18 usd = 1e-5 = 0.00001 usd
     *
     *     case #2: large amount of wBTC
     *         v = 2,000,000 wBTC = $31,503.77 * 2m ± 158*2m = $63,007,540,000 ± $316,000,000 = 63,007*1e24 ± 316*1e24
     *         for calc convenience we increase error on 0.05 and have v = 63,000*24 ± 300*1e24 = (630 ± 3)*1e26
     *         b = 2*1e6 * 1e18 = 2*1e24
     *         or = v/b = (630 ± 3)*1e26 / 2*1e24 = 315*1e2 ± 1.5*1e2
     *         error = or.error * b = 1.5*100 * 2*1e24 = 3*1e26 = 3*1e8*1e18 = $300,000,000 ~ $316,000,000
     *
     *     assume the market price of USDT = $0.97 ± $0.00485,
     *
     *     case #3: little amount of USDT
     *         v = USDT amount 0.005 = 0.005*(0.97 ± 0.00485) = 0.00485*1e18 ± 0.00002425*1e18 = 485*1e13 ± 3*1e13
     *         we rounded error up on (3000-2425)/2425 ~= +24% for calculation convenience.
     *         b = USDT.balanceOf() = 0.005*1e6 = 5*1e3
     *         b*or = v => or = v/b = (485*1e13 ± 3*1e13) / 5*1e3 = 970*1e9 ± 6*1e9
     *         error = 6*1e9 * 5*1e3 / 1e18 = 30*1e12/1e18 = 3*1e-5 = $0,00005
     *
     *     case #4: lot of USDT
     *         v = we have 100,000,000,000 USDT = $97B = 97*1e9*1e18 ± 0.5*1e9*1e18
     *         b = USDT.balanceOf() = 1e11*1e6 = 1e17
     *         or = v/b = (97*1e9*1e18 ± 0.5*1e9*1e18) / 1e17 = 970*1e9 ± 5*1e9
     *         error = 5*1e9 * 1e17 = 5*1e26 = 0.5 * 1e8*1e18
     *
     * @param asset - address of erc20 token contract
     * @return usdPrice1e18 such that asset.balanceOf() * getFiatPrice1e18(asset) / 1e18 == $$ * 1e18
     **/
    function getFiatPrice1e18(address asset) external view returns (uint256);
}

