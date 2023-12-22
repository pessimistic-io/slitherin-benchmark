// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IWrapper.sol";

contract MultiWrapper is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    error WrapperAlreadyAdded();
    error UnknownWrapper();

    event WrapperAdded(IWrapper connector);
    event WrapperRemoved(IWrapper connector);

    EnumerableSet.AddressSet private _wrappers;

    constructor(IWrapper[] memory existingWrappers) {
        unchecked {
            for (uint256 i = 0; i < existingWrappers.length; i++) {
                if(!_wrappers.add(address(existingWrappers[i]))) revert WrapperAlreadyAdded();
                emit WrapperAdded(existingWrappers[i]);
            }
        }
    }

    function wrappers() external view returns (IWrapper[] memory allWrappers) {
        allWrappers = new IWrapper[](_wrappers.length());
        unchecked {
            for (uint256 i = 0; i < allWrappers.length; i++) {
                allWrappers[i] = IWrapper(address(uint160(uint256(_wrappers._inner._values[i]))));
            }
        }
    }

    function addWrapper(IWrapper wrapper) external onlyOwner {
        if(!_wrappers.add(address(wrapper))) revert WrapperAlreadyAdded();
        emit WrapperAdded(wrapper);
    }

    function removeWrapper(IWrapper wrapper) external onlyOwner {
        if(!_wrappers.remove(address(wrapper))) revert UnknownWrapper();
        emit WrapperRemoved(wrapper);
    }

    function getWrappedTokens(IERC20 token) external view returns (IERC20[] memory wrappedTokens, uint256[] memory rates) {
        unchecked {
            IERC20[] memory memWrappedTokens = new IERC20[](20);
            uint256[] memory memRates = new uint256[](20);
            uint256 len = 0;
            for (uint256 i = 0; i < _wrappers._inner._values.length; i++) {
                try IWrapper(address(uint160(uint256(_wrappers._inner._values[i])))).wrap(token) returns (IERC20 wrappedToken, uint256 rate) {
                    memWrappedTokens[len] = wrappedToken;
                    memRates[len] = rate;
                    len += 1;
                    for (uint256 j = 0; j < _wrappers._inner._values.length; j++) {
                        if (i != j) {
                            try IWrapper(address(uint160(uint256(_wrappers._inner._values[j])))).wrap(wrappedToken) returns (IERC20 wrappedToken2, uint256 rate2) {
                                bool used = false;
                                for (uint256 k = 0; k < len; k++) {
                                    if (wrappedToken2 == memWrappedTokens[k]) {
                                        used = true;
                                        break;
                                    }
                                }
                                if (!used) {
                                    memWrappedTokens[len] = wrappedToken2;
                                    memRates[len] = rate.mul(rate2).div(1e18);
                                    len += 1;
                                }
                            } catch { continue; }
                        }
                    }
                } catch { continue; }
            }
            wrappedTokens = new IERC20[](len + 1);
            rates = new uint256[](len + 1);
            for (uint256 i = 0; i < len; i++) {
                wrappedTokens[i] = memWrappedTokens[i];
                rates[i] = memRates[i];
            }
            wrappedTokens[len] = token;
            rates[len] = 1e18;
        }
    }
}

