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

    event OpenBet(
        address indexed user,
        address indexed pool,
        address asset,
        uint256 amount,
        string symbolName,
        int256 tradeVolume,
        address client
    );

    event CloseBet(
        address indexed user,
        address indexed pool,
        address asset,
        uint256 amount,
        string symbolName,
        int256 tradeVolume,
        address client
    );

    using SafeERC20 for IERC20;

    address public immutable clientTemplate;

    address public immutable clientImplementation;

    constructor (
        address clientTemplate_,
        address clientImplementation_
    ) NameVersion('BrokerImplementation', '3.0.1')
    {
        clientTemplate = clientTemplate_;
        clientImplementation = clientImplementation_;
    }

    function openBet(
        address pool,
        address asset,
        uint256 amount,
        string memory symbolName,
        int256 tradeVolume,
        int256 priceLimit,
        IPool.OracleSignature[] memory oracleSignatures
    ) external payable {
        bytes32 symbolId = keccak256(abi.encodePacked(symbolName));
        Bet storage bet = bets[msg.sender][pool][symbolId];
        int256 volume = getVolume(msg.sender, pool, symbolId);
        require(volume == 0, 'BrokerImplementation.openBet: existed bet');

        bet.asset = asset;
        address client;
        if (bet.client == address(0)) {
            client = _clone(clientTemplate);
            bet.client = client;
        } else {
            client = bet.client;
        }

        if (asset == address(0)) {
            amount = msg.value;
            _transfer(address(0), client, amount);
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, client, amount);
        }

        IClient(client).addMargin(pool, asset, amount, oracleSignatures);
        IClient(client).trade(pool, symbolName, tradeVolume, priceLimit, oracleSignatures);

        emit OpenBet(msg.sender, pool, asset, amount, symbolName, tradeVolume, client);
    }

    function closeBet(
        address pool,
        string memory symbolName,
        int256 priceLimit,
        IPool.OracleSignature[] memory oracleSignatures
    ) external {
        bytes32 symbolId = keccak256(abi.encodePacked(symbolName));
        Bet memory bet = bets[msg.sender][pool][symbolId];
        int256 volume = getVolume(msg.sender, pool, symbolId);
        require(volume != 0, 'BrokerImplementation.closeBet: no bet');

        IClient(bet.client).trade(pool, symbolName, -volume, priceLimit, oracleSignatures);
        IClient(bet.client).removeMargin(pool, bet.asset, type(uint256).max, oracleSignatures);

        uint256 balance = bet.asset == address(0) ? bet.client.balance : IERC20(bet.asset).balanceOf(bet.client);
        IClient(bet.client).transfer(bet.asset, msg.sender, balance);

        emit CloseBet(msg.sender, pool, bet.asset, balance, symbolName, -volume, bet.client);
    }

    function getBetVolumes(address account, address pool, string[] memory symbols) external view returns (int256[] memory) {
        int256[] memory volumes = new int256[](symbols.length);
        for (uint256 i = 0; i < symbols.length; i++) {
            volumes[i] = getVolume(account, pool, keccak256(abi.encodePacked(symbols[i])));
        }
        return volumes;
    }

    function getVolume(address account, address pool, bytes32 symbolId) public view returns (int256 volume) {
        Bet storage bet = bets[account][pool][symbolId];
        address client = bet.client;
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
    // 1: User never entered bet, no client
    // 2: User is holding a betting volume
    // 3: User closed bet normally
    // 4: User is liquidated
    // 0: Wrong query, e.g. wrong symbolId etc.
    function getUserStatus(address account, address pool, bytes32 symbolId) public view returns (uint256 status) {
        Bet storage bet = bets[account][pool][symbolId];
        address client = bet.client;
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

    function transfer(address asset, address to, uint256 amount) external _onlyAdmin_ {
        _transfer(asset, to, amount);
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

    // amount in asset's own decimals
    function _transfer(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            (bool success, ) = payable(to).call{value: amount}('');
            require(success, 'BrokerImplementation.transfer: send ETH fail');
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

}

interface IPoolComplement {
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

