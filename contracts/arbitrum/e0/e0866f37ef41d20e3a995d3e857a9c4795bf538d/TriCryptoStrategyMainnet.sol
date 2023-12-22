pragma solidity ^0.5.16;

import "./IMainnetStrategy.sol";
import "./TriCryptoStrategy.sol";


contract TriCryptoStrategyMainnet is TriCryptoStrategy, IMainnetStrategy {

    function initializeMainnetStrategy(
        address _storage,
        address _vault,
        address _strategist
    ) external initializer {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = CRV;
        CurveStrategy.initializeCurveStrategy(
            _storage,
            CRV_TRI_CRYPTO_TOKEN,
            _vault,
            CRV_TRI_CRYPTO_GAUGE,
            rewardTokens,
            _strategist,
            CRV_TRI_CRYPTO_POOL,
            WETH,
            /* depositArrayPosition = */ 2
        );
    }

}

