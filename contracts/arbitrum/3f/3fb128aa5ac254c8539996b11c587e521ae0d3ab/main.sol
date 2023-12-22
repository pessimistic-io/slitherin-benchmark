pragma solidity ^0.8.17;

import { Address } from "./Address.sol";

// Import ERC20 interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract StringDecoder { 

    function _bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        bytes32 _temp;
        uint256 count;
        for (uint256 i; i < 32; i++) {
            _temp = _bytes32[i];
            if (_temp != bytes32(0)) {
                count += 1;
            }
        }
        bytes memory bytesArray = new bytes(count);
        for (uint256 i; i < count; i++) {
            bytesArray[i] = (_bytes32[i]);
        }
        return (string(bytesArray));
    }

    function _decodeStringNormal(bytes memory data) public pure returns(string memory) {
        return abi.decode(data, (string));
    }

    function _decodeStringLib(bytes memory data) public pure returns(string memory) {
        return _bytes32ToString(abi.decode(data, (bytes32)));
    }
}

contract TokenBalanceResolver is StringDecoder {
    struct TokenBalance {
        uint256 balance;
        bool success;
    }

    struct UserTokenBalances {
        address user;
        TokenBalance[] balances;
    }

    struct TokenInfo {
        bool isToken;
        string name;
        string symbol;
        uint256 decimals;
    }

    address private constant ETHER_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getBalances(address user, address[] memory tokenAddresses) public returns (UserTokenBalances memory) {
        return UserTokenBalances(user, _getBalances(user, tokenAddresses));
    }

    function getBalancesForMultipleUsers(address[] memory users, address[] memory tokenAddresses) public returns (UserTokenBalances[] memory) {
        UserTokenBalances[] memory allUserBalances = new UserTokenBalances[](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            allUserBalances[i].user = users[i];
            allUserBalances[i].balances = _getBalances(users[i], tokenAddresses);
        }

        return allUserBalances;
    }

    function getTokenInfo(address token) public returns (TokenInfo memory) {
        if (Address.isContract(token)) {
            (bool successName, bytes memory nameData) = token.call(abi.encodeWithSignature("name()"));
            (bool successSymbol, bytes memory symbolData) = token.call(abi.encodeWithSignature("symbol()"));
            (bool successDecimals, bytes memory decimalsData) = token.call(abi.encodeWithSignature("decimals()"));

            if (successName && successSymbol && successDecimals) {
                (bool nameDecode, string memory name)= decodeString(nameData);
                (bool symbolDecode, string memory symbol) = decodeString(symbolData);
                uint256 decimals = abi.decode(decimalsData, (uint256));

                return TokenInfo(true && nameDecode && symbolDecode, name, symbol, decimals);
            }
        }
        return TokenInfo(false, "", "", 0);
    }

    function getMultipleTokenInfo(address[] memory tokens) public returns (TokenInfo[] memory) {
        TokenInfo[] memory tokenInfos = new TokenInfo[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokenInfos[i] = getTokenInfo(tokens[i]);
        }

        return tokenInfos;
    }

    function _getBalances(address user, address[] memory tokenAddresses) private returns (TokenBalance[] memory) {
        TokenBalance[] memory balances = new TokenBalance[](tokenAddresses.length);

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == ETHER_ADDRESS) {
                balances[i].balance = user.balance;
                balances[i].success = true;
            } else {
                if(Address.isContract(tokenAddresses[i])) {
                    bytes memory callData = abi.encodeWithSelector(IERC20(tokenAddresses[i]).balanceOf.selector, user);
                    (bool success, bytes memory result) = tokenAddresses[i].call(callData);

                    if (success) {
                        balances[i].balance = abi.decode(result, (uint256));
                        balances[i].success = true;
                    }
                }
            }
        }

        return balances;
    }

    function decodeString(bytes memory data) public returns(bool status, string memory) {
        (bool success, bytes memory stringData) = address(this).call(abi.encodeWithSelector(StringDecoder._decodeStringNormal.selector, data));

        if (success) {
            return (true, abi.decode(stringData, (string)));
        } else {
            (success, stringData) = address(this).call(abi.encodeWithSelector(StringDecoder._decodeStringLib.selector, data));
            if (success) {
                return (true, abi.decode(stringData, (string)));
            } else {
                return (false, "");
            }
        }
    }
}


