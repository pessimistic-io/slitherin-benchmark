// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./LBErrors.sol";

error JoeDexLens__PairsNotCreated();
error JoeDexLens__UnknownDataFeedType();
error JoeDexLens__CollateralNotInPair(address pair, address collateral);
error JoeDexLens__TokenNotInPair(address pair, address token);
error JoeDexLens__SameTokens();
error JoeDexLens__DataFeedAlreadyAdded(address colateral, address token, address dataFeed);
error JoeDexLens__DataFeedNotInSet(address colateral, address token, address dataFeed);
error JoeDexLens__LengthsMismatch();
error JoeDexLens__NullWeight();
error JoeDexLens__WrongPair();
error JoeDexLens__InvalidChainLinkPrice();
error JoeDexLens__NotEnoughLiquidity();

