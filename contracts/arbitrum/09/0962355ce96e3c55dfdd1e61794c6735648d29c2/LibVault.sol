// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Bits.sol";
import "./Constants.sol";
import "./TransferHelper.sol";
import "./IWBNB.sol";
import {FeatureSwitches, IVault} from "./IVault.sol";
import "./ITrading.sol";
import "./ITradingCore.sol";
import "./ITradingClose.sol";
import "./LibPriceFacade.sol";
import "./IERC20Metadata.sol";
import {ZERO, ONE, UC, uc, into} from "./UC.sol";

library LibVault {

    using Bits for uint;

    bytes32 constant VAULT_POSITION = keccak256("apollox.vault.storage");

    struct AvailableToken {
        address tokenAddress;
        uint32 tokenAddressPosition;
        uint16 weight;
        uint16 feeBasisPoints;
        uint16 taxBasisPoints;
        uint8 decimals;
        bool stable;
        bool dynamicFee;
        uint8 featureSwitches;
    }

    struct VaultStorage {
        mapping(address => AvailableToken) tokens;
        address[] tokenAddresses;
        // tokenAddress => amount
        mapping(address => uint256) treasury;
        address wbnb;             // obsolete
        address exchangeTreasury; // obsolete
        uint16 securityMarginP;   // 1e4
    }

    function vaultStorage() internal pure returns (VaultStorage storage vs) {
        bytes32 position = VAULT_POSITION;
        assembly {
            vs.slot := position
        }
    }

    event AddToken(
        address indexed token, uint16 weight, uint16 feeBasisPoints,
        uint16 taxBasisPoints, bool stable, bool dynamicFee, uint8 featureSwitches
    );
    event RemoveToken(address indexed token);
    event UpdateToken(
        address indexed token,
        uint16 oldFeeBasisPoints, uint16 oldTaxBasisPoints, bool oldDynamicFee,
        uint16 feeBasisPoints, uint16 taxBasisPoints, bool dynamicFee
    );
    event UpdateTokenFeature(address indexed tokenAddress, uint8 featureSwitches);
    event ChangeWeight(address[] tokenAddress, uint16[] oldWeights, uint16[] newWeights);
    event SetSecurityMarginP(uint16 oldSecurityMarginP, uint16 securityMarginP);
    event CloseTradeRemoveLiquidity(address indexed token, uint256 amount);

    function addToken(
        address tokenAddress, uint16 feeBasisPoints, uint16 taxBasisPoints, bool stable,
        bool dynamicFee, uint8 featureSwitches, uint16[] calldata weights
    ) internal {
        VaultStorage storage vs = vaultStorage();
        AvailableToken storage at = vs.tokens[tokenAddress];
        require(at.tokenAddress == address(0), "LibVault: Can't add token that already exists");
        at.tokenAddress = tokenAddress;
        at.tokenAddressPosition = uint32(vs.tokenAddresses.length);
        at.feeBasisPoints = feeBasisPoints;
        at.taxBasisPoints = taxBasisPoints;
        at.decimals = IERC20Metadata(tokenAddress).decimals();
        at.stable = stable;
        at.dynamicFee = dynamicFee;
        at.featureSwitches = featureSwitches;

        vs.tokenAddresses.push(tokenAddress);
        emit AddToken(at.tokenAddress, weights[weights.length - 1], at.feeBasisPoints, at.taxBasisPoints, at.stable, at.dynamicFee, featureSwitches);
        changeWeight(weights);
    }

    function removeToken(address tokenAddress, uint16[] calldata weights) internal {
        VaultStorage storage vs = vaultStorage();
        AvailableToken storage at = vs.tokens[tokenAddress];
        require(at.tokenAddress != address(0), "LibVault: Token does not exist");

        changeWeight(weights);
        uint256 lastPosition = vs.tokenAddresses.length - 1;
        uint256 tokenAddressPosition = at.tokenAddressPosition;
        if (tokenAddressPosition != lastPosition) {
            address lastTokenAddress = vs.tokenAddresses[lastPosition];
            vs.tokenAddresses[tokenAddressPosition] = lastTokenAddress;
            vs.tokens[lastTokenAddress].tokenAddressPosition = uint32(tokenAddressPosition);
        }
        require(at.weight == 0, "LibVault: The weight of the removed Token must be 0.");
        vs.tokenAddresses.pop();
        delete vs.tokens[tokenAddress];
        emit RemoveToken(tokenAddress);
    }

    function updateToken(address tokenAddress, uint16 feeBasisPoints, uint16 taxBasisPoints, bool dynamicFee) internal {
        VaultStorage storage vs = vaultStorage();
        AvailableToken storage at = vs.tokens[tokenAddress];
        require(at.tokenAddress != address(0), "LibVault: Token does not exist");
        (uint16 oldFeePoints, uint16 oldTaxPoints, bool oldDynamicFee) = (at.feeBasisPoints, at.taxBasisPoints, at.dynamicFee);
        at.feeBasisPoints = feeBasisPoints;
        at.taxBasisPoints = taxBasisPoints;
        at.dynamicFee = dynamicFee;
        emit UpdateToken(tokenAddress, oldFeePoints, oldTaxPoints, oldDynamicFee, feeBasisPoints, taxBasisPoints, dynamicFee);
    }

    function updateTokenFeature(address tokenAddress, uint8 featureSwitches) internal {
        AvailableToken storage at = vaultStorage().tokens[tokenAddress];
        require(at.tokenAddress != address(0), "LibVault: Token does not exist");
        require(at.featureSwitches != featureSwitches, "LibVault: No modification required");
        at.featureSwitches = featureSwitches;
        emit UpdateTokenFeature(tokenAddress, featureSwitches);
    }

    function changeWeight(uint16[] calldata weights) internal {
        VaultStorage storage vs = vaultStorage();
        require(weights.length == vs.tokenAddresses.length, "LibVault: Invalid weights");
        uint16 totalWeight;
        uint16[] memory oldWeights = new uint16[](weights.length);
        for (UC i = ZERO; i < uc(weights.length); i = i + ONE) {
            totalWeight += weights[i.into()];
            address tokenAddress = vs.tokenAddresses[i.into()];
            uint16 oldWeight = vs.tokens[tokenAddress].weight;
            oldWeights[i.into()] = oldWeight;
            vs.tokens[tokenAddress].weight = weights[i.into()];
        }
        require(totalWeight == 1e4, "LibVault: The sum of the weights is not equal to 10000");
        emit ChangeWeight(vs.tokenAddresses, oldWeights, weights);
    }

    function setSecurityMarginP(uint16 securityMarginP) internal {
        VaultStorage storage vs = vaultStorage();
        uint16 old = vs.securityMarginP;
        vs.securityMarginP = securityMarginP;
        emit SetSecurityMarginP(old, securityMarginP);
    }

    function decreaseByCloseTrade(address token, uint256 amount) internal returns (ITradingClose.SettleToken[] memory settleTokens) {
        VaultStorage storage vs = vaultStorage();
        uint8 token_0_decimals = vs.tokens[token].decimals;
        ITradingClose.SettleToken memory st = ITradingClose.SettleToken(
            token,
            vs.treasury[token] >= amount ? amount : vs.treasury[token],
            token_0_decimals
        );
        if (vs.treasury[token] >= amount) {
            vs.treasury[token] -= amount;
            settleTokens = new ITradingClose.SettleToken[](1);
            settleTokens[0] = st;
            emit CloseTradeRemoveLiquidity(token, amount);
            return settleTokens;
        } else {
            uint256 otherTokenAmountUsd = (amount - vs.treasury[token]) * LibPriceFacade.getPrice(token) * 1e10 / (10 ** token_0_decimals);
            address[] memory allTokens = vs.tokenAddresses;
            ITrading.MarginBalance[] memory balances = new ITrading.MarginBalance[](allTokens.length - 1);
            uint256 totalBalanceUsd;
            UC index = ZERO;
            for (UC i = ZERO; i < uc(allTokens.length); i = i + ONE) {
                address tokenAddress = allTokens[i.into()];
                AvailableToken memory at = vs.tokens[tokenAddress];
                if (uint(at.featureSwitches).bitSet(uint8(FeatureSwitches.AS_MARGIN)) && tokenAddress != token && vs.treasury[tokenAddress] > 0) {
                    uint256 balanceUsd = vs.treasury[tokenAddress] * LibPriceFacade.getPrice(tokenAddress) * 1e10 / (10 ** at.decimals);
                    balances[index.into()] = ITrading.MarginBalance(tokenAddress, LibPriceFacade.getPrice(tokenAddress), at.decimals, balanceUsd);
                    totalBalanceUsd += balanceUsd;
                    index = index + ONE;
                }
            }
            require(otherTokenAmountUsd <= totalBalanceUsd, "LibVault: Insufficient funds in the treasury");
            settleTokens = new ITradingClose.SettleToken[]((index + ONE).into());
            settleTokens[0] = st;
            vs.treasury[token] = 0;
            emit CloseTradeRemoveLiquidity(token, settleTokens[0].amount);

            uint points = 1e4;
            for (UC i = ONE; i < index; i = i + ONE) {
                ITrading.MarginBalance memory mb = balances[i.into()];
                uint256 share = mb.balanceUsd * 1e4 / totalBalanceUsd;
                settleTokens[i.into()] = ITradingClose.SettleToken(mb.token, otherTokenAmountUsd * share * (10 ** mb.decimals) / (1e4 * 1e10 * mb.price), mb.decimals);
                vs.treasury[mb.token] -= settleTokens[i.into()].amount;
                emit CloseTradeRemoveLiquidity(mb.token, settleTokens[i.into()].amount);
                points -= share;
            }
            ITrading.MarginBalance memory b = balances[0];
            settleTokens[index.into()] = ITradingClose.SettleToken(b.token, otherTokenAmountUsd * points * (10 ** b.decimals) / (1e4 * 1e10 * b.price), b.decimals);
            vs.treasury[b.token] -= settleTokens[index.into()].amount;
            emit CloseTradeRemoveLiquidity(b.token, settleTokens[index.into()].amount);
            return settleTokens;
        }
    }

    function getTotalValueUsd() internal view returns (int256) {
        LibVault.VaultStorage storage vs = vaultStorage();
        uint256 numTokens = vs.tokenAddresses.length;
        uint256 totalValueUsd;
        for (UC i = ZERO; i < uc(numTokens); i = i + ONE) {
            address tokenAddress = vs.tokenAddresses[i.into()];
            LibVault.AvailableToken storage at = vs.tokens[tokenAddress];
            uint256 price = LibPriceFacade.getPrice(tokenAddress);
            uint256 balance = vs.treasury[tokenAddress];
            uint256 valueUsd = price * balance * 1e10 / (10 ** at.decimals);
            totalValueUsd += valueUsd;
        }
        return int256(totalValueUsd);
    }

    function getTokenByAddress(address tokenAddress) internal view returns (AvailableToken memory) {
        return LibVault.vaultStorage().tokens[tokenAddress];
    }

    function maxWithdrawAbleUsd(int256 totalValueUsd) internal view returns (int256) {
        LibVault.VaultStorage storage vs = vaultStorage();
        return totalValueUsd - int256(ITradingCore(address(this)).lpNotionalUsd() * vs.securityMarginP / 1e4);
    }
}

