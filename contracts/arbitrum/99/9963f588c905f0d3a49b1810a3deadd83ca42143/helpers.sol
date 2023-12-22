//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Variables} from "./variables.sol";
import "./IERC20.sol";

contract Helper is Variables {
    function getBalancerAvailability(address[] memory _tokens, uint256[] memory _amounts) internal view returns (bool) {
        for(uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token_ = IERC20(_tokens[i]);
            if (token_.balanceOf(balancerLendingAddr) < _amounts[i]) {
                return false;
            }
        }
        return true;
    }

    function getRoutesWithAvailability(uint16[] memory _routes, address[] memory _tokens, uint256[] memory _amounts) internal view returns (uint16[] memory) {
        uint16[] memory routesWithAvailability_ = new uint16[](7);
        uint j = 0;
        for(uint256 i = 0; i < _routes.length; i++) {
            if (_routes[i] == 5) {
                if(getBalancerAvailability(_tokens, _amounts)) {
                    routesWithAvailability_[j] = _routes[i];
                    j++;
                }
            } else {
                require(false, "invalid-route");
            }
        }
        return routesWithAvailability_;
    }

    function bubbleSort(address[] memory _tokens, uint256[] memory _amounts) internal pure returns (address[] memory, uint256[] memory) {
        for (uint256 i = 0; i < _tokens.length - 1; i++) {
            for( uint256 j = 0; j < _tokens.length - i - 1 ; j++) {
                if(_tokens[j] > _tokens[j+1]) {
                    (_tokens[j], _tokens[j+1], _amounts[j], _amounts[j+1]) = (_tokens[j+1], _tokens[j], _amounts[j+1], _amounts[j]);
                }
            }
        }
        return (_tokens, _amounts);
    }

    function validateTokens(address[] memory _tokens) internal pure {
        for (uint i = 0; i < _tokens.length - 1; i++) {
            require(_tokens[i] != _tokens[i+1], "non-unique-tokens");
        }
    }
}
