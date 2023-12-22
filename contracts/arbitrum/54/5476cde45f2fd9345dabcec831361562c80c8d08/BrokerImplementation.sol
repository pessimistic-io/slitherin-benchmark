// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./NameVersion.sol";
import "./IERC20.sol";
import "./IDToken.sol";
import "./IPool.sol";
import "./SafeERC20.sol";
import "./BrokerStorage.sol";
import "./IClient.sol";

contract BrokerImplementation is BrokerStorage, NameVersion {

    event Trade(
        address indexed user,
        address indexed pool,
        address asset,
        uint256 inAmount,
        uint256 outAmount,
        string symbolName,
        int256 tradeVolume,
        address client
    );

    using SafeERC20 for IERC20;

    address public immutable clientTemplate;

    address public immutable clientImplementation;

    address public immutable swapper;

    constructor (
        address clientTemplate_,
        address clientImplementation_,
        address swapper_
    ) NameVersion('BrokerImplementation', '3.0.1')
    {
        clientTemplate = clientTemplate_;
        clientImplementation = clientImplementation_;
        swapper = swapper_;
    }

    function approveSwapper(address asset) external _onlyAdmin_ {
        uint256 allowance = IERC20(asset).allowance(address(this), swapper);
        if (allowance != type(uint256).max) {
            if (allowance != 0) {
                IERC20(asset).safeApprove(swapper, 0);
            }
            IERC20(asset).safeApprove(swapper, type(uint256).max);
        }
    }

    function trade(
        address pool,
        address asset,
        bool isWithdraw,
        uint256 amount,
        string memory symbolName,
        int256 tradeVolume,
        int256 priceLimit,
        IPool.OracleSignature[] memory oracleSignatures
    ) external payable {
        bytes32 symbolId = keccak256(abi.encodePacked(symbolName));
        address tokenB0 = IPoolComplement(pool).tokenB0();
        address client = clients[msg.sender][pool][symbolId];

        // Add margin and trade
        if (!isWithdraw) {
            require(asset == tokenB0, 'BrokerImplementation.trade: only tokenB0 as margin');
            if (client == address(0)) {
                client = _clone(clientTemplate);
                clients[msg.sender][pool][symbolId] = client;
            }
            IERC20(tokenB0).safeTransferFrom(msg.sender, client, amount);
            IClient(client).addMargin(pool, tokenB0, amount, oracleSignatures);
            IClient(client).trade(pool, symbolName, tradeVolume, priceLimit, new IPool.OracleSignature[](0));

            emit Trade(msg.sender, pool, asset, amount, 0, symbolName, tradeVolume, client);
        }
        // Trade and withdraw
        else {
            IClient(client).trade(pool, symbolName, tradeVolume, priceLimit, oracleSignatures);
            IClient(client).removeMargin(pool, tokenB0, amount, new IPool.OracleSignature[](0));

            uint256 balance = IERC20(tokenB0).balanceOf(client);
            uint256 outAmount;
            if (asset == tokenB0) {
                outAmount = balance;
                IClient(client).transfer(tokenB0, msg.sender, balance);
            } else {
                IClient(client).transfer(tokenB0, address(this), balance);
                (, outAmount) = ISwapper(swapper).swapExactB0ForBX(asset, balance);
                IERC20(asset).safeTransfer(msg.sender, outAmount);
            }

            emit Trade(msg.sender, pool, asset, 0, outAmount, symbolName, tradeVolume, client);
        }
    }

    //================================================================================
    // Convenient Functions
    //================================================================================
    function getVolumes(address account, address pool, string[] memory symbols) external view returns (int256[] memory) {
        int256[] memory volumes = new int256[](symbols.length);
        for (uint256 i = 0; i < symbols.length; i++) {
            volumes[i] = getVolume(account, pool, keccak256(abi.encodePacked(symbols[i])));
        }
        return volumes;
    }

    function getVolume(address account, address pool, bytes32 symbolId) public view returns (int256 volume) {
        address client = clients[account][pool][symbolId];
        if (client != address(0)) {
            IDToken pToken = IDToken(IPoolComplement(pool).pToken());
            uint256 pTokenId = pToken.getTokenIdOf(client);
            if (pTokenId != 0) {
                address symbol = ISymbolManagerComplement(IPoolComplement(pool).symbolManager()).symbols(symbolId);
                if (symbol != address(0)) {
                    ISymbolComplement.Position memory p = ISymbolComplement(symbol).positions(pTokenId);
                    volume = p.volume;
                }
            }
        }
    }

    function getUserStatuses(address account, address pool, string[] memory symbols) external view returns (uint256[] memory) {
        uint256[] memory statuses = new uint256[](symbols.length);
        for (uint256 i = 0; i < symbols.length; i++) {
            statuses[i] = getUserStatus(account, pool, keccak256(abi.encodePacked(symbols[i])));
        }
        return statuses;
    }

    // Return value:
    // 1: User never traded, no client
    // 2: User is holding a position
    // 3: User closed position normally
    // 4: User is liquidated
    // 0: Wrong query, e.g. wrong symbolId etc.
    function getUserStatus(address account, address pool, bytes32 symbolId) public view returns (uint256 status) {
        address client = clients[account][pool][symbolId];
        if (client == address(0)) {
            status = 1;
        } else {
            IDToken pToken = IDToken(IPoolComplement(pool).pToken());
            uint256 pTokenId = pToken.getTokenIdOf(client);
            if (pTokenId != 0) {
                address symbol = ISymbolManagerComplement(IPoolComplement(pool).symbolManager()).symbols(symbolId);
                if (symbol != address(0)) {
                    ISymbolComplement.Position memory p = ISymbolComplement(symbol).positions(pTokenId);
                    if (p.volume != 0) {
                        status = 2;
                    } else {
                        status = p.cumulativeFundingPerVolume != 0 ? 3 : 4;
                    }
                }
            }
        }
    }


    //================================================================================
    // Helpers
    //================================================================================

    function claimRewardAsLpVenus(address pool, address[] memory clients) external _onlyAdmin_ {
        for (uint256 i = 0; i < clients.length; i++) {
            IClient(clients[i]).claimRewardAsLpVenus(pool);
        }
    }

    function claimRewardAsTraderVenus(address pool, address[] memory clients) external _onlyAdmin_ {
        for (uint256 i = 0; i < clients.length; i++) {
            IClient(clients[i]).claimRewardAsTraderVenus(pool);
        }
    }

    function claimRewardAsLpAave(address pool, address[] memory clients) external _onlyAdmin_ {
        for (uint256 i = 0; i < clients.length; i++) {
            IClient(clients[i]).claimRewardAsLpAave(pool);
        }
    }

    function claimRewardAsTraderAave(address pool, address[] memory clients) external _onlyAdmin_ {
        for (uint256 i = 0; i < clients.length; i++) {
            IClient(clients[i]).claimRewardAsTraderAave(pool);
        }
    }

    function _clone(address source) internal returns (address target) {
        bytes20 sourceBytes = bytes20(source);
        assembly {
            let c := mload(0x40)
            mstore(c, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(c, 0x14), sourceBytes)
            mstore(add(c, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            target := create(0, c, 0x37)
        }
    }

}

interface IPoolComplement {
    function tokenB0() external view returns (address);
    function pToken() external view returns (address);
    function symbolManager() external view returns (address);
}

interface ISymbolManagerComplement {
    function symbols(bytes32 symbolId) external view returns (address);
}

interface ISymbolComplement {
    struct Position {
        int256 volume;
        int256 cost;
        int256 cumulativeFundingPerVolume;
    }
    function positions(uint256 pTokenId) external view returns (Position memory);
}

interface ISwapper {
    function swapExactB0ForBX(address tokenBX, uint256 amountB0)
    external returns (uint256 resultB0, uint256 resultBX);
}

