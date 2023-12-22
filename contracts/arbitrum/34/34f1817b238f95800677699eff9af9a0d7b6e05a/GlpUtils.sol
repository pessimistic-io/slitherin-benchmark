// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IVaultReader} from "./IVaultReader.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {GlpTokenAllocation} from "./GlpTokenAllocation.sol";
import {ERC20} from "./ERC20.sol";
import {PositionType} from "./PositionType.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract GlpUtils is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IVaultReader private vaultReader;
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
}

