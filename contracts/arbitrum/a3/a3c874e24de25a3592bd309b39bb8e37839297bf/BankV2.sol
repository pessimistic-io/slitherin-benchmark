// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {AccessControlEnumerable} from "./AccessControlEnumerable.sol";
import {IERC20Metadata, IERC20} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Multicall} from "./Multicall.sol";

import {KeeperCompatibleInterface} from "./KeeperCompatible.sol";

import "./IRouter.sol";
import "./IPool.sol";


contract BankV2 {
    using SafeERC20 for IERC20;

    /// @notice Token's house edge allocations struct.
    /// The games house edge is split into several allocations.
    /// The allocated amounts stays in the bank until authorized parties withdraw. They are subtracted from the balance.
    /// @param bank Rate to be allocated to the bank, on bet payout.
    /// @param dividend Rate to be allocated as staking rewards, on bet payout.
    /// @param treasury Rate to be allocated to the treasury, on bet payout.
    /// @param team Rate to be allocated to the team, on bet payout.
    /// @param dividendAmount The number of tokens to be sent as staking rewards.
    /// @param treasuryAmount The number of tokens to be sent to the treasury.
    /// @param teamAmount The number of tokens to be sent to the team. 
    struct HouseEdgeSplit {
        uint16 bank;
        uint16 dividend;
        uint16 treasury;
        uint16 team;
        uint256 dividendAmount;
        uint256 treasuryAmount;
        uint256 teamAmount;
    }

    struct Token {
        bool allowed;
        bool paused;
        uint16 balanceRisk;
        uint256 minBetAmount;
        HouseEdgeSplit houseEdgeSplit;
    }

    struct TokenMetadata {
        uint8 decimals;
        address tokenAddress;
        string name;
        string symbol;
        Token token;
    }

    /// @notice Number of tokens added.
    uint8 private _tokensCount;

    /// @notice Treasury multi-sig wallet.
    address public  treasury;

    address public router;

    /// @notice Team wallet.
    address public teamWallet;

    /// @notice Maps tokens addresses to token configuration.
    mapping(address => Token) public tokens;

    /// @notice Maps tokens indexes to token address.
    mapping(uint8 => address) private _tokensList;

    /// @notice Emitted after a token is added.
    /// @param token Address of the token.
    event AddToken(address token);

    /// @notice Emitted after the balance risk is set.
    /// @param balanceRisk Rate defining the balance risk.
    event SetBalanceRisk(address indexed token, uint16 balanceRisk);

    /// @notice Emitted after a token is allowed.
    /// @param token Address of the token.
    /// @param allowed Whether the token is allowed for betting.
    event SetAllowedToken(address indexed token, bool allowed);

    /// @notice Emitted after the minimum bet amount is set for a token.
    /// @param token Address of the token.
    /// @param minBetAmount Minimum bet amount.
    event SetTokenMinBetAmount(address indexed token, uint256 minBetAmount);

    /// @notice Emitted after a token deposit.
    /// @param token Address of the token.
    /// @param amount The number of token deposited.
    event Deposit(address indexed token, uint256 amount);

    /// @notice Emitted after a token withdrawal.
    /// @param token Address of the token.
    /// @param amount The number of token withdrawn.
    event Withdraw(address indexed token, uint256 amount);

    event SetTokenHouseEdgeSplit(
        address indexed token,
        uint16 bank,
        uint16 dividend,
        uint16 treasury,
        uint16 team
    );

    /// @notice Emitted after the token's treasury and team allocations are distributed.
    /// @param token Address of the token.
    /// @param treasuryAmount The number of tokens sent to the treasury.
    /// @param teamAmount The number of tokens sent to the team.
    event HouseEdgeDistribution(
        address indexed token,
        uint256 treasuryAmount,
        uint256 teamAmount
    );

    /// @notice Emitted after the token's dividend allocation is distributed.
    /// @param token Address of the token.
    /// @param amount The number of tokens sent to the SwirlMaster.
    event HarvestDividend(address indexed token, uint256 amount);

    /// @notice Emitted after the token's house edge is allocated.
    /// @param token Address of the token.
    /// @param bank The number of tokens allocated to bank.
    /// @param dividend The number of tokens allocated as staking rewards.
    /// @param treasury The number of tokens allocated to the treasury.
    /// @param team The number of tokens allocated to the team.
    event AllocateHouseEdgeAmount(
        address indexed token,
        uint256 bank,
        uint256 dividend,
        uint256 treasury,
        uint256 team
    );

    /// @notice Emitted after the game's fees are sent to the bank.
    /// @param token Address of the token.
    /// @param newBalance New token balance.
    /// @param fees Fees received from game.
    event AccountFees(address indexed token, uint256 newBalance, uint256 fees);

    /// @notice Emitted after the bet profit amount is sent to the user.
    /// @param token Address of the token.
    /// @param newBalance New token balance.
    /// @param profit Bet profit amount sent.
    event Payout(address indexed token, uint256 newBalance, uint256 profit);

    /// @notice Emitted after the bet amount is collected from the game smart contract.
    /// @param token Address of the token.
    /// @param newBalance New token balance.
    /// @param amount Bet amount collected.
    event CashIn(address indexed token, uint256 newBalance, uint256 amount);

    /// @notice Reverting error when trying to add an existing token.
    error TokenExists();
    /// @notice Reverting error when setting the house edge allocations, but the sum isn't 100%.
    /// @param splitSum Sum of the house edge allocations rates.
    error WrongHouseEdgeSplit(uint16 splitSum);
    /// @notice Reverting error when sender isn't allowed.
    error AccessDenied();
    /// @notice Reverting error when team wallet or treasury is the zero address.
    error WrongAddress();
    /// @notice Reverting error when withdrawing a non paused token.
    error TokenNotPaused();
    /// @notice Reverting error when token has pending bets on a game.
    error TokenHasPendingBets();

    /// @notice Emitted after the team wallet is set.
    /// @param teamWallet The team wallet address.
    event SetTeamWallet(address teamWallet);

    /// @notice Initialize the contract's admin role to the deployer, and state variables.
    /// @param teamWalletAddress Team wallet.
    constructor( address teamWalletAddress) {

        // The ownership should then be transfered to a multi-sig.
        // _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        setTeamWallet(teamWalletAddress);
    }

    /// @notice Transfers a specific amount of token to an address.
    /// Uses native transfer or ERC20 transfer depending on the token.
    /// @dev The 0x address is considered the gas token.
    /// @param user Address of destination.
    /// @param token Address of the token.
    /// @param amount Number of tokens.
    function _safeTransfer(
        address user,
        address token,
        uint256 amount
    ) private {
        if (_isGasToken(token)) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }

    /// @notice Check if the token has the 0x address.
    /// @param token Address of the token.
    /// @return Whether the token's address is the 0x address.
    function _isGasToken(address token) private pure returns (bool) {
        return token == address(0);
    }

    /// @notice Deposit funds in the bank to allow gamers to win more.
    /// ERC20 token allowance should be given prior to deposit.
    /// @param token Address of the token.
    /// @param amount Number of tokens.
    function deposit(address token, uint256 amount)
        external
        payable
    // onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        if (_isGasToken(token)) {
            amount = msg.value;
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit Deposit(token, amount);
    }

    /// @notice Withdraw funds from the bank. Token has to be paused and no pending bet resolution on games.
    /// @param token Address of the token.
    /// @param amount Number of tokens.
    function withdraw(address token, uint256 amount)
        public
    // onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        uint256 balance = getBalance(token);
        if (balance != 0) {
            if (!tokens[token].paused) {
                revert TokenNotPaused();
            }

            // uint256 roleMemberCount = getRoleMemberCount(GAME_ROLE);
            // for (uint256 i; i < roleMemberCount; i++) {
            //     if (IGame(getRoleMember(GAME_ROLE, i)).hasPendingBets(token)) {
            //         revert TokenHasPendingBets();
            //     }
            // }
        }

        if (amount > balance) {
            amount = balance;
        }
        _safeTransfer(msg.sender, token, amount);
        emit Withdraw(token, amount);
    }

    /// @notice Sets the new token balance risk.
    /// @param token Address of the token.
    /// @param balanceRisk Risk rate.
    function setBalanceRisk(address token, uint16 balanceRisk)
        external
    // onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].balanceRisk = balanceRisk;
        emit SetBalanceRisk(token, balanceRisk);
    }

    /// @notice Adds a new token that'll be enabled for the games' betting.
    /// Token shouldn't exist yet.
    /// @param token Address of the token.
    function addToken(
        address token // onlyRole(DEFAULT_ADMIN_ROLE)
    ) external {
        if (_tokensCount != 0) {
            for (uint8 i; i < _tokensCount; i++) {
                if (_tokensList[i] == token) {
                    revert TokenExists();
                }
            }
        }
        _tokensList[_tokensCount] = token;
        _tokensCount += 1;
        emit AddToken(token);
    }

    /// @notice Changes the token's bet permission.
    /// @param token Address of the token.
    /// @param allowed Whether the token is enabled for bets.
    function setAllowedToken(address token, bool allowed)
        external
    // onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokens[token].allowed = allowed;
        emit SetAllowedToken(token, allowed);
    }

    /// @notice Sets the token's house edge allocations for bet payout.
    /// @param token Address of the token.
    /// @param bank Rate to be allocated to the bank, on bet payout.
    /// @param dividend Rate to be allocated as staking rewards, on bet payout.
    /// @param _treasury Rate to be allocated to the treasury, on bet payout.
    /// @param team Rate to be allocated to the team, on bet payout.
    /// @dev `bank`, `dividend`, `_treasury` and `team` rates sum must equals 10000.
    function setHouseEdgeSplit(
        address token,
        uint16 bank,
        uint16 dividend,
        uint16 _treasury,
        uint16 team
    ) external {
        uint16 splitSum = bank + dividend + team + _treasury;
        if (splitSum != 10000) {
            revert WrongHouseEdgeSplit(splitSum);
        }

        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;
        tokenHouseEdge.bank = bank;
        tokenHouseEdge.dividend = dividend;
        tokenHouseEdge.treasury = _treasury;
        tokenHouseEdge.team = team;

        emit SetTokenHouseEdgeSplit(token, bank, dividend, _treasury, team);
    }

    /// @notice Sets the minimum bet amount for a specific token.
    /// @param token Address of the token.
    /// @param tokenMinBetAmount Minimum bet amount.
    function setTokenMinBetAmount(address token, uint256 tokenMinBetAmount)
        external
    // onlyTokenOwner(DEFAULT_ADMIN_ROLE, token)
    {
        tokens[token].minBetAmount = tokenMinBetAmount;
        emit SetTokenMinBetAmount(token, tokenMinBetAmount);
    }

    /// @notice Harvests tokens dividends.
    /// @return The list of tokens addresses.
    /// @return The list of tokens' amounts harvested.
    function harvestDividends()
        external
        returns (
            // onlyRole(SWIRLMASTER_ROLE)
            address[] memory,
            uint256[] memory
        )
    {
        address[] memory _tokens = new address[](_tokensCount);
        uint256[] memory _amounts = new uint256[](_tokensCount);

        for (uint8 i; i < _tokensCount; i++) {
            address tokenAddress = _tokensList[i];
            Token storage token = tokens[tokenAddress];
            uint256 dividendAmount = token.houseEdgeSplit.dividendAmount;
            if (dividendAmount != 0) {
                delete token.houseEdgeSplit.dividendAmount;
                _safeTransfer(msg.sender, tokenAddress, dividendAmount);
                emit HarvestDividend(tokenAddress, dividendAmount);
                _tokens[i] = tokenAddress;
                _amounts[i] = dividendAmount;
            }
        }

        return (_tokens, _amounts);
    }

    /// @notice Get the available tokens dividends amounts.
    /// @return The list of tokens addresses.
    /// @return The list of tokens' amounts harvested.
    function getDividends()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory _tokens = new address[](_tokensCount);
        uint256[] memory _amounts = new uint256[](_tokensCount);

        for (uint8 i; i < _tokensCount; i++) {
            address tokenAddress = _tokensList[i];
            Token storage token = tokens[tokenAddress];
            uint256 dividendAmount = token.houseEdgeSplit.dividendAmount;
            if (dividendAmount != 0) {
                _tokens[i] = tokenAddress;
                _amounts[i] = dividendAmount;
            }
        }

        return (_tokens, _amounts);
    }

    /// @notice Splits the house edge fees and allocates them as dividends, to the partner, the bank, the treasury, and team.
    /// @param token Address of the token.
    /// @param fees Bet amount and bet profit fees amount.
    function _allocateHouseEdge(address token, uint256 fees) private {
        HouseEdgeSplit storage tokenHouseEdge = tokens[token].houseEdgeSplit;

        uint256 dividendAmount = (fees * tokenHouseEdge.dividend) / 10000;
        tokenHouseEdge.dividendAmount += dividendAmount;

        // The bank also get allocated a share of the house edge.
        uint256 bankAmount = (fees * tokenHouseEdge.bank) / 10000;

        uint256 treasuryAmount = (fees * tokenHouseEdge.treasury) / 10000;
        tokenHouseEdge.treasuryAmount += treasuryAmount;

        uint256 teamAmount = (fees * tokenHouseEdge.team) / 10000;
        tokenHouseEdge.teamAmount += teamAmount;

        emit AllocateHouseEdgeAmount(
            token,
            bankAmount,
            dividendAmount,
            treasuryAmount,
            teamAmount
        );
    }

    /// @notice Receive game's fees.
    /// @param token Address of the token.
    /// @param fees Bet amount and bet profit fees amount.
    function accountFees(address token, uint256 fees)
        external
        
        payable
    // onlyRole(GAME_ROLE)
    {
        _allocateHouseEdge(token, fees);

        emit AccountFees(
            token,
            getBalance(token),
            _isGasToken(token) ? msg.value : fees
        );
    }

    /// @notice Payouts a winning bet, and allocate the house edge fee.
    /// @param user Address of the gamer.
    /// @param token Address of the token.
    /// @param profit Number of tokens to be sent to the gamer.
    /// @param fees Bet amount and bet profit fees amount.
    function payout(
        address payable user,
        address token,
        uint256 profit,
        uint256 fees // onlyRole(GAME_ROLE)
    ) external payable {
        _allocateHouseEdge(token, fees);

        // Pay the user
        // _safeTransfer(user, token, profit);
        address pool = IRouter(router).getPool(token);
        IPool(pool).creditUserProfit(user, profit);
        emit Payout(token, getBalance(token), profit);

    }

    /// @notice Accounts a loss bet.
    /// @dev In case of an ERC20, the bet amount should be transfered prior to this tx.
    /// @dev In case of the gas token, the bet amount is sent along with this tx.
    /// @param tokenAddress Address of the token.
    /// @param amount Loss bet amount.
    function cashIn(address tokenAddress, uint256 amount)
        external
        payable
    // onlyRole(GAME_ROLE)
    {
        emit CashIn(
            tokenAddress,
            getBalance(tokenAddress),
            _isGasToken(tokenAddress) ? msg.value : amount
        );
    }

    /// @dev For the front-end
    function getTokens() external view returns (TokenMetadata[] memory) {
        TokenMetadata[] memory _tokens = new TokenMetadata[](_tokensCount);
        for (uint8 i; i < _tokensCount; i++) {
            address tokenAddress = _tokensList[i];
            Token memory token = tokens[tokenAddress];
            if (_isGasToken(tokenAddress)) {
                _tokens[i] = TokenMetadata({
                    decimals: 18,
                    tokenAddress: tokenAddress,
                    name: "ETH",
                    symbol: "ETH",
                    token: token
                });
            } else {
                IERC20Metadata erc20Metadata = IERC20Metadata(tokenAddress);
                _tokens[i] = TokenMetadata({
                    decimals: erc20Metadata.decimals(),
                    tokenAddress: tokenAddress,
                    name: erc20Metadata.name(),
                    symbol: erc20Metadata.symbol(),
                    token: token
                });
            }
        }
        return _tokens;
    }

    /// @notice Gets the token's min bet amount.
    /// @param token Address of the token.
    /// @return minBetAmount Min bet amount.
    /// @dev The min bet amount should be at least 10000 cause of the `getMaxBetAmount` calculation.
    function getMinBetAmount(address token)
        external
        view
        returns (uint256 minBetAmount)
    {
        minBetAmount = tokens[token].minBetAmount;
        if (minBetAmount == 0) {
            minBetAmount = 10000;
        }
    }

    /// @notice Calculates the max bet amount based on the token balance, the balance risk, and the game multiplier.
    /// @param token Address of the token.
    /// @param multiplier The bet amount leverage determines the user's profit amount. 10000 = 100% = no profit.
    /// @return Maximum bet amount for the token.
    /// @dev The multiplier should be at least 10000.
    function getMaxBetAmount(address token, uint256 multiplier)
        external
        view
        returns (uint256)
    {
        return (getBalance(token) * tokens[token].balanceRisk) / multiplier;
    }

    /// @notice Gets the token's allow status used on the games smart contracts.
    /// @param tokenAddress Address of the token.
    /// @return Whether the token is enabled for bets.
    function isAllowedToken(address tokenAddress) external view returns (bool) {
        Token memory token = tokens[tokenAddress];
        return token.allowed && !token.paused;
    }

    // /// @notice Gets the token's owner.
    // /// @param token Address of the token.
    // /// @return Address of the owner.
    // function getTokenOwner(address token) external view returns (address) {
    //     address partner = tokens[token].partner;
    //     if (partner == address(0)) {
    //         return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    //     } else {
    //         return partner;
    //     }
    // }

    /// @notice Sets the new team wallet.
    /// @param _teamWallet The team wallet address.
    function setTeamWallet(address _teamWallet)
        public
    // onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_teamWallet == address(0)) {
            revert WrongAddress();
        }
        teamWallet = _teamWallet;
        emit SetTeamWallet(teamWallet);
    }

    function setTreasury(address tAddress)
    public 
    {   
        if (tAddress == address(0)) {
            revert WrongAddress();
        }
        treasury = tAddress;
    }

   function setRouter (address routerAddress)
    public 
    {   
        if (routerAddress == address(0)) {
            revert WrongAddress();
        }
        router = routerAddress;
        treasury = IRouter(router).treasury();
    }

    /// @notice Distributes the token's treasury and team allocations amounts.
    /// @param tokenAddress Address of the token.
    function withdrawHouseEdgeAmount(address tokenAddress) public {
        HouseEdgeSplit storage tokenHouseEdge = tokens[tokenAddress]
            .houseEdgeSplit;
        uint256 treasuryAmount = tokenHouseEdge.treasuryAmount;
        uint256 teamAmount = tokenHouseEdge.teamAmount;
        if (treasuryAmount != 0) {
            delete tokenHouseEdge.treasuryAmount;
            _safeTransfer(treasury, tokenAddress, treasuryAmount);
        }
        if (teamAmount != 0) {
            delete tokenHouseEdge.teamAmount;
            _safeTransfer(teamWallet, tokenAddress, teamAmount);
        }
        if (treasuryAmount != 0 || teamAmount != 0) {
            emit HouseEdgeDistribution(
                tokenAddress,
                treasuryAmount,
                teamAmount
            );
        }
    }

    /// @notice Gets the token's balance.
    /// The token's house edge allocation amounts are subtracted from the balance.
    /// @param token Address of the token.
    /// @return The amount of token available for profits.
    function getBalance(address token) public view returns (uint256) {
        uint256 balance;
        if (_isGasToken(token)) {
            balance = address(this).balance;
        } else {
            address pool = IRouter(router).getPool(token);
            balance = IERC20(token).balanceOf(pool);
        }
        HouseEdgeSplit memory tokenHouseEdgeSplit = tokens[token]
            .houseEdgeSplit;
        return
            balance -
            tokenHouseEdgeSplit.dividendAmount -
            tokenHouseEdgeSplit.treasuryAmount -
            tokenHouseEdgeSplit.teamAmount;
    }
}

