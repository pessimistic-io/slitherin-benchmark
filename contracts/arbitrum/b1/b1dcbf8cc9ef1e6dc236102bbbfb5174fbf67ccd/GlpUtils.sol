// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IVaultReader} from "./IVaultReader.sol";
import {IVault} from "./IVault.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {GlpTokenAllocation} from "./GlpTokenAllocation.sol";
import {ERC20} from "./ERC20.sol";
import {PositionType} from "./PositionType.sol";
import {PRICE_PRECISION,BASIS_POINTS_DIVISOR} from "./Constants.sol";
import {SafeMath} from "./SafeMath.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract GlpUtils is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;

    IVaultReader private vaultReader;
    IVault private vault;
    address private vaultAddress;
    address private positionManagerAddress;
    address private wethAddress;

    uint256 private constant GLP_DIVISOR = 1 * 10**18;
    uint256 private constant VAULT_PROPS_LENGTH = 14;
    uint256 private constant PERCENT_MULTIPLIER = 10000;

    function initialize(
        address _vaultReaderAddress,
        address _vaultAddress,
        address _positionManagerAddress,
        address _wethAddress
    ) public initializer {
        vaultReader = IVaultReader(_vaultReaderAddress);
        vaultAddress = _vaultAddress;
        positionManagerAddress = _positionManagerAddress;
        wethAddress = _wethAddress;
        vault = IVault(_vaultAddress);

        __Ownable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getGlpTokenAllocations(address[] memory tokens)
        public
        view
        returns (GlpTokenAllocation[] memory)
    {
        uint256[] memory tokenInfo = vaultReader.getVaultTokenInfoV3(
            vaultAddress,
            positionManagerAddress,
            wethAddress,
            GLP_DIVISOR,
            tokens
        );

        GlpTokenAllocation[]
            memory glpTokenAllocations = new GlpTokenAllocation[](
               tokens.length 
            );

        uint256 totalSupply = 0;
        for (uint256 index = 0; index < tokens.length; index++) {
            totalSupply += tokenInfo[index * VAULT_PROPS_LENGTH + 2];
        }

        for (uint256 index = 0; index < tokens.length; index++) {
            uint256 poolAmount = tokenInfo[index * VAULT_PROPS_LENGTH];
            uint256 usdgAmount = tokenInfo[index * VAULT_PROPS_LENGTH + 2];
            uint256 weight = tokenInfo[index * VAULT_PROPS_LENGTH + 4];
            uint256 allocation = (usdgAmount * PERCENT_MULTIPLIER) /
                totalSupply;

            glpTokenAllocations[index] = GlpTokenAllocation({
                tokenAddress: tokens[index],
                poolAmount: poolAmount,
                usdgAmount: usdgAmount,
                weight: weight,
                allocation: allocation
            });
        }

        return glpTokenAllocations;
    }

    function getGlpTokenExposure(
        uint256 glpPositionWorth,
        address[] memory tokens
    ) external view returns (TokenExposure[] memory) {
        GlpTokenAllocation[] memory tokenAllocations = getGlpTokenAllocations(
            tokens
        );
        TokenExposure[] memory tokenExposures = new TokenExposure[](
            tokenAllocations.length
        );

        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            tokenExposures[i] = TokenExposure({
                amount: int256((glpPositionWorth * tokenAllocations[i].allocation) /
                    PERCENT_MULTIPLIER),
                token: tokenAllocations[i].tokenAddress,
                symbol: ERC20(tokenAllocations[i].tokenAddress).symbol()
            });
        }

        return tokenExposures;
    }

    function setVault(address _vaultAddress) external {
        vault = IVault(_vaultAddress);
        vaultAddress = _vaultAddress;
    }

    function getFeeBasisPoints(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint256 priceIn = vault.getMinPrice(tokenIn);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        uint256 usdgAmount = amountIn.mul(priceIn).div(PRICE_PRECISION);
        address usdg = vault.usdg();
        usdgAmount = vault.adjustForDecimals(usdgAmount, tokenIn, usdg);

        bool isStableSwap = vault.stableTokens(tokenIn) && vault.stableTokens(tokenOut);
        uint256 feeBasisPoints;
        {
            uint256 baseBps = isStableSwap ? vault.stableSwapFeeBasisPoints() : vault.swapFeeBasisPoints();
            uint256 taxBps = isStableSwap ? vault.stableTaxBasisPoints() : vault.taxBasisPoints();
            uint256 feesBasisPoints0 = vault.getFeeBasisPoints(tokenIn, usdgAmount, baseBps, taxBps, true);
            uint256 feesBasisPoints1 = vault.getFeeBasisPoints(tokenOut, usdgAmount, baseBps, taxBps, false);
            // use the higher of the two fee basis points
            feeBasisPoints = feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
        }
        return feeBasisPoints;
    }

    function getAmountInAfterFees(address tokenIn, address tokenOut, uint256 amountOut) public view returns (uint256) {
        uint256 priceIn = vault.getMinPrice(tokenIn);
        uint256 priceOut = vault.getMaxPrice(tokenOut);

        uint256 amountIn = amountOut * priceOut / priceIn;
        amountIn = vault.adjustForDecimals(amountIn, tokenIn, tokenOut);
        uint256 feeBasisPoints = getFeeBasisPoints(tokenIn, tokenOut, amountIn);
        return amountIn * (BASIS_POINTS_DIVISOR + feeBasisPoints) / BASIS_POINTS_DIVISOR;
    }
}

