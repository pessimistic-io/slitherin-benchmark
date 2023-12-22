// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from "./contracts_DataTypes.sol";
import "./console.sol";

library LibOracleState {
    function findTokenAmount(DataTypes.OracleState memory self, address _token) internal pure returns (uint256) {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            if (self.tokens[i] == _token) {
                return self.tokensAmount[i];
            }
        }
        return 0;
    }

    function addTokenAmount(DataTypes.OracleState memory self, address _token, uint256 _amount) internal pure {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            if (self.tokens[i] == _token) {
                self.tokensAmount[i] += _amount;
                return;
            }
        }

        address[] memory newTokens = new address[](self.tokens.length + 1);
        uint256[] memory newTokensAmount = new uint256[](
            self.tokens.length + 1
        );

        for (uint256 i = 0; i < self.tokens.length; i++) {
            newTokens[i] = self.tokens[i];
            newTokensAmount[i] = self.tokensAmount[i];
        }

        newTokens[self.tokens.length] = _token;
        newTokensAmount[self.tokens.length] = _amount;

        self.tokens = newTokens;
        self.tokensAmount = newTokensAmount;
    }

    function setTokenAmount(DataTypes.OracleState memory self, address _token, uint256 _amount) internal pure {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            if (self.tokens[i] == _token) {
                self.tokensAmount[i] = _amount;
                return;
            }
        }

        address[] memory newTokens = new address[](self.tokens.length + 1);
        uint256[] memory newTokensAmount = new uint256[](
            self.tokens.length + 1
        );

        for (uint256 i = 0; i < self.tokens.length; i++) {
            newTokens[i] = self.tokens[i];
            newTokensAmount[i] = self.tokensAmount[i];
        }

        newTokens[self.tokens.length] = _token;
        newTokensAmount[self.tokens.length] = _amount;

        self.tokens = newTokens;
        self.tokensAmount = newTokensAmount;
    }

    function removeTokenAmount(DataTypes.OracleState memory self, address _token, uint256 _amount) internal pure {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            if (self.tokens[i] == _token) {
                self.tokensAmount[i] -= _amount;
            }
        }
    }

    function removeTokenPercent(DataTypes.OracleState memory self, address _token, uint256 _percent) internal pure {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            if (self.tokens[i] == _token) {
                self.tokensAmount[i] = (self.tokensAmount[i] * _percent) / 10000;
            }
        }
    }

    function removeAllTokenPercent(DataTypes.OracleState memory self, uint256 _percent) internal pure {
        for (uint256 i = 0; i < self.tokens.length; i++) {
            self.tokensAmount[i] = (self.tokensAmount[i] * _percent) / 10000;
        }
    }
}

