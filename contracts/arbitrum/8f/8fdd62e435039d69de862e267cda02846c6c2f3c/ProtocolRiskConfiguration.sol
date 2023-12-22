/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import {UD60x18} from "./UD60x18.sol";

/**
 * @title Tracks protocol-wide risk settings
 */
library ProtocolRiskConfiguration {
    struct Data {
        /**
         * @dev IM Multiplier is used to introduce a buffer between the liquidation (LM) and initial (IM) margin requirements
         * where IM = imMultiplier * LM
         */
        UD60x18 imMultiplier;
        /**
         * @dev Liquidator reward parameters are multiplied by the im delta caused by the liquidation to get the liquidator reward
         * amount
         */
        UD60x18 liquidatorRewardParameter;
    }

    /**
     * @dev Loads the ProtocolRiskConfiguration object.
     * @return config The ProtocolRiskConfiguration object.
     */
    function load() internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.ProtocolRiskConfiguration"));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the protocol-wide risk configuration
     * @param config The ProtocolRiskConfiguration object with all the protocol-wide risk parameters
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();
        storedConfig.imMultiplier = config.imMultiplier;
        storedConfig.liquidatorRewardParameter = config.liquidatorRewardParameter;
    }
}

