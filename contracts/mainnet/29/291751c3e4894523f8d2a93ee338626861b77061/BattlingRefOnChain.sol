// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./AggregatorV3Interface.sol";
import "./ERC20.sol";
import "./SignerVerifiable.sol";

contract Battling is SignerVerifiable {
    struct Battle {
        address player_one;
        address player_two;
        address player_one_referral_address;
        address player_two_referral_address;
        address token_address;
        uint value;
        bool cancelled;
        bool paid;
    }

    struct FuncParams {
        bytes _signature;
        uint256 _amount;
        uint256 _deadline;
        string _message;
        string _battle_id;
        address _erc20_token;
        address _player_referral_address;
    }

    mapping(address => int) public total_wagered_under_account_code;

    mapping(string => Battle) public battle_contestants;
    mapping(address => bool) public erc20_token_supported;
    mapping(address => address) public token_to_aggregator_address;

    mapping(address => uint) public partnership_fee_tier;

    bool public contract_frozen = false;
    
    // MODIFY THESE WHEN DEPLOYING THE CONTRACT
    address public SIGNER = 0x950bb768cEda61410E451520aBc138d7700D249B;
    address public TREASURY = 0x064bfB0820e6c4ADCAA34086729995d6fD21823E;

    uint256 public battle_fee_precent = 10;
    uint256 public reduced_battle_fee_percent = 5;

    address public OWNER;

    // MODIFIERS
    
    function _onlyOwner() internal view {
        require(msg.sender == OWNER || msg.sender == SIGNER, "Caller is not the owner");
    }
    
    function _isCallerVerified(uint256 _amount, string calldata _message, string calldata _battle_id, uint256 _deadline, address _erc20_token, address _player_referral_address, bytes calldata _signature) internal {
        require(msg.sender == tx.origin, "No smart contract interactions allowed");
        require(!contract_frozen, "Contract is paused");
        require(decodeSignature(msg.sender, _amount, _message, _battle_id, _deadline, _erc20_token, _player_referral_address, _signature) == SIGNER, "Call is not authorized");
    }

    // END MODIFIERS

    constructor () {
        OWNER = msg.sender;
    }

    // AUTHORIZED FUNCTIONS
    function initiateBattleERC20(FuncParams calldata fp) external {
        _isCallerVerified(fp._amount, fp._message, fp._battle_id, fp._deadline, fp._erc20_token, fp._player_referral_address, fp._signature);
        
        require(battle_contestants[fp._battle_id].player_one == address(0) || battle_contestants[fp._battle_id].player_two == address(0), "Battle is full");
        require(!battle_contestants[fp._battle_id].cancelled, "Battle was cancelled");

        if (battle_contestants[fp._battle_id].value == 0) { // battle creation
            require(fp._amount > 0, "Amount must be greater than 0");
            require(erc20_token_supported[fp._erc20_token], "Token is not supported");
            battle_contestants[fp._battle_id].value = fp._amount;
            battle_contestants[fp._battle_id].token_address = fp._erc20_token;
        } else { // battle joining
            require(battle_contestants[fp._battle_id].player_one != msg.sender, "Cannot join own battle");
            require(battle_contestants[fp._battle_id].value == fp._amount, "Incorrect value sent to battle");
            require(battle_contestants[fp._battle_id].token_address == fp._erc20_token, "Wrong token");
        }

        ERC20(fp._erc20_token).transferFrom(msg.sender, address(this), fp._amount);
        
        if (battle_contestants[fp._battle_id].player_one == address(0)) {
            battle_contestants[fp._battle_id].player_one = msg.sender;
            battle_contestants[fp._battle_id].player_one_referral_address = fp._player_referral_address;
        } else {
            battle_contestants[fp._battle_id].player_two = msg.sender;
            battle_contestants[fp._battle_id].player_two_referral_address = fp._player_referral_address;
        }
    }

    function initiateBattleETH(FuncParams calldata fp) external payable {
        _isCallerVerified(msg.value, fp._message, fp._battle_id, fp._deadline, address(0), fp._player_referral_address, fp._signature);
        require(battle_contestants[fp._battle_id].player_one == address(0x0) || battle_contestants[fp._battle_id].player_two == address(0x0), "Battle is full");
        require(!battle_contestants[fp._battle_id].cancelled, "Battle was cancelled");
        
        if (battle_contestants[fp._battle_id].value == 0) { // battle creation
            require(msg.value > 0, "Amount must be greater than 0");
            battle_contestants[fp._battle_id].value = msg.value;
        } else { // battle joining
            require(battle_contestants[fp._battle_id].player_one != msg.sender, "Cannot join own battle");
            require(battle_contestants[fp._battle_id].value == msg.value, "Incorrect value sent to battle");
        }

        if (battle_contestants[fp._battle_id].player_one == address(0)) {
            battle_contestants[fp._battle_id].player_one = msg.sender;
            battle_contestants[fp._battle_id].player_one_referral_address = fp._player_referral_address;
        } else {
            battle_contestants[fp._battle_id].player_two = msg.sender;
            battle_contestants[fp._battle_id].player_two_referral_address = fp._player_referral_address;
        }
    }
    
    function claimWinnings(FuncParams calldata fp) external {
        unchecked {
            _isCallerVerified(battle_contestants[fp._battle_id].value, fp._message, fp._battle_id, fp._deadline, battle_contestants[fp._battle_id].token_address, fp._player_referral_address, fp._signature);
            require(!battle_contestants[fp._battle_id].paid, "Rewards already claimed for battle");
            require(!battle_contestants[fp._battle_id].cancelled, "Battle was cancelled, cannot claim winnings");
            require(battle_contestants[fp._battle_id].player_one == msg.sender || battle_contestants[fp._battle_id].player_two == msg.sender, "User is not in this battle");
            
            battle_contestants[fp._battle_id].paid = true;

            uint battle_value = 2 * battle_contestants[fp._battle_id].value;

            address ref = fp._player_referral_address;
            
            // Use the reduced fee if there is a referral code present, otherwise use the normal fee
            uint fee_to_use = ref != address(0) ? reduced_battle_fee_percent : battle_fee_precent;
            
            if (ref == address(0)) ref = TREASURY;

            address token_address = battle_contestants[fp._battle_id].token_address;

            // ETH wagers
            if (token_address == address(0)) {
                uint amount_owed_to_winner = battle_value * (100 - fee_to_use) / 100;
                uint amount_owed_to_ref = _calculateRefOwedAmount(ref, battle_value * fee_to_use / 100);
                uint amount_owed_to_treasury = battle_value * fee_to_use / 100 - amount_owed_to_ref;

                // transfer winnings to user
                payable(msg.sender).transfer(amount_owed_to_winner);

                // transfer referral designated amount
                if (amount_owed_to_ref > 0) payable(ref).transfer(amount_owed_to_ref);

                // transfer treasury designated amount
                if (amount_owed_to_treasury > 0) payable(TREASURY).transfer(amount_owed_to_treasury);

                // Update referral wager balance, if the token has a corresponding aggregator address
                if (token_to_aggregator_address[token_address] != address(0)) {
                    int latest_price = getLatestPrice(token_address);
                    total_wagered_under_account_code[battle_contestants[fp._battle_id].player_one_referral_address] += int(battle_value / 2) * latest_price / _pow(18);
                    total_wagered_under_account_code[battle_contestants[fp._battle_id].player_two_referral_address] += int(battle_value / 2) * latest_price / _pow(18);
                }

            } else { // ERC20 wagers
                uint amount_owed_to_winner = battle_value * (100 - fee_to_use) / 100;
                uint amount_owed_to_ref = _calculateRefOwedAmount(ref, battle_value * fee_to_use / 100);
                uint amount_owed_to_treasury = battle_value * fee_to_use / 100 - amount_owed_to_ref;

                // transfer winnings to user
                ERC20(token_address).transfer(msg.sender, amount_owed_to_winner);

                // transfer referral designated amount
                if (amount_owed_to_ref > 0) ERC20(token_address).transfer(ref, amount_owed_to_ref);

                // transfer treasury designated amount
                if (amount_owed_to_ref > 0) ERC20(token_address).transfer(TREASURY, amount_owed_to_treasury);

                // Update referral wager balance, if the token has a corresponding aggregator address
                if (token_to_aggregator_address[token_address] != address(0)) {
                    int latest_price = getLatestPrice(token_address);
                    total_wagered_under_account_code[battle_contestants[fp._battle_id].player_one_referral_address] += int(battle_value / 2) * latest_price / _pow(ERC20(token_address).decimals());
                    total_wagered_under_account_code[battle_contestants[fp._battle_id].player_two_referral_address] += int(battle_value / 2) * latest_price / _pow(ERC20(token_address).decimals());
                }
            }
        }
    }

    function cancelBattle(FuncParams calldata fp) external {
        _isCallerVerified(battle_contestants[fp._battle_id].value, fp._message, fp._battle_id, fp._deadline, battle_contestants[fp._battle_id].token_address, fp._player_referral_address, fp._signature);
        uint value = battle_contestants[fp._battle_id].value;

        require(value > 0, "Battle does not exist");
        require(!battle_contestants[fp._battle_id].cancelled, "Battle was already cancelled");
        require(!battle_contestants[fp._battle_id].paid, "Battle was already paid");
        require(battle_contestants[fp._battle_id].player_one == msg.sender && battle_contestants[fp._battle_id].player_two == address(0), "Cannot cancel this battle");

        battle_contestants[fp._battle_id].cancelled = true;

        address token_address = battle_contestants[fp._battle_id].token_address;

        if (token_address == address(0)) {
            payable(msg.sender).transfer(value);
        } else {
            ERC20(token_address).transfer(msg.sender, value);
        }
    }


    // END AUTHORIZED FUNCTIONS



    // REFERRAL CODE FUNCTIONS


    function _pow(uint8 _exponent) internal pure returns(int) {
        return int(10 ** _exponent);
    }

    // Get the fee portion owed to the referral address by computing the accumulated wagers under their code
    function _calculateRefOwedAmount(address _ref_address, uint _fee_amount) internal view returns(uint) {
        if (_ref_address == address(0) || _ref_address == TREASURY) return 0;
        if (partnership_fee_tier[_ref_address] > 0) {
            return 5 * partnership_fee_tier[_ref_address] * _fee_amount / 100;
        }

        uint[9] memory REFERRAL_TIERS_AMT_REQUIRED = [uint(2_000), uint(5_000), uint(7_500), uint(10_000), uint(20_000), uint(40_000), uint(60_000), uint(80_000), uint(100_000)];
        uint total_wagered = uint(total_wagered_under_account_code[_ref_address]);
        uint tier_num = 10;
        
        for (uint i = 0; i < 9; ++i) {
            if (total_wagered < REFERRAL_TIERS_AMT_REQUIRED[i] * (10 ** 18)) {
                tier_num = i + 1;
                break;
            }
        }

        return 5 * tier_num * _fee_amount / 100;
    }

    // Get latest price of some token through ChainLink price feed
    function getLatestPrice(address _token_address) public view returns (int) {
        address aggregator_address = token_to_aggregator_address[_token_address];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(aggregator_address);
        (,int price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        return price * (10 ** 18) / _pow(decimals);
    }


    // END REFERRAL CODE FUNCTIONS

    

    // OWNER FUNCTIONS

    function setAggregatorAddress(address _token, address _aggregator_address) external {
        _onlyOwner();
        token_to_aggregator_address[_token] = _aggregator_address;
    }

    function toggleSupportedToken(address _token) external {
        _onlyOwner();
        erc20_token_supported[_token] = !erc20_token_supported[_token];
    }

    function toggleContractFreeze() external {
        _onlyOwner();
        contract_frozen = !contract_frozen;
    }
    
    function setSignerAddress(address _new_signer) external {
        _onlyOwner();
        SIGNER = _new_signer;
    }

    function setTreasuryAddress(address _new_wallet) external {
        _onlyOwner();
        TREASURY = _new_wallet;
    }

    function setBattleFee(uint256 _new_fee) external {
        _onlyOwner();
        require(_new_fee <= 100, "Invalid percentage");
        battle_fee_precent = _new_fee;
    }

    function setReducedBattleFee(uint256 _new_fee) external {
        _onlyOwner();
        require(_new_fee <= 100, "Invalid percentage");
        reduced_battle_fee_percent = _new_fee;
    }

    function setPartnershipFeeTier(address _partner, uint _fee_tier) external {
        _onlyOwner();
        partnership_fee_tier[_partner] = _fee_tier;
    }

    // Emergency withdraw funds to users in case it gets stuck in escrow and battle does not play out
    function emergencyRefundUnfinishedBattle(string memory _battle_id) external {
        _onlyOwner();

        require(!battle_contestants[_battle_id].paid, "Battle was already paid");
        require(!battle_contestants[_battle_id].cancelled, "Battle was already cancelled");

        battle_contestants[_battle_id].cancelled = true;

        address player_one = battle_contestants[_battle_id].player_one;
        address player_two = battle_contestants[_battle_id].player_two;
        address token_address = battle_contestants[_battle_id].token_address;
        uint amt_to_refund_each = battle_contestants[_battle_id].value;

        if (player_one != address(0)) {
            if (token_address == address(0)) {
                payable(player_one).transfer(amt_to_refund_each);
            } else {
                ERC20(token_address).transfer(player_one, amt_to_refund_each);
            }
        }
        
        if (player_two != address(0)) {
            if (token_address == address(0)) {
                payable(player_two).transfer(amt_to_refund_each);
            } else {
                ERC20(token_address).transfer(player_two, amt_to_refund_each);
            }
        }
    }

    // Emergency payout winner in case the claimWinnings function doesn't work
    function emergencyPayOutUnpaidBattle(string memory _battle_id, address _winner) external {
        _onlyOwner();

        require(!battle_contestants[_battle_id].paid, "Battle was already paid out");
        require(!battle_contestants[_battle_id].cancelled, "Battle was already cancelled");

        battle_contestants[_battle_id].paid = true;

        address player_one = battle_contestants[_battle_id].player_one;
        address player_two = battle_contestants[_battle_id].player_two;

        require(_winner == player_one || _winner == player_two, "Winner was not one of the addresses");
        require(player_one != address(0) && player_two != address(0), "No one actually joined the battle");

        address token_address = battle_contestants[_battle_id].token_address;
        uint amt_to_pay_out = 2 * (100 - reduced_battle_fee_percent) * battle_contestants[_battle_id].value / 100;
        uint amt_to_take_fee = 2 * reduced_battle_fee_percent * battle_contestants[_battle_id].value / 100;

        if (token_address == address(0)) {
            payable(_winner).transfer(amt_to_pay_out);
            payable(TREASURY).transfer(amt_to_take_fee);
        } else {
            ERC20(token_address).transfer(_winner, amt_to_pay_out);
            ERC20(token_address).transfer(TREASURY, amt_to_take_fee);
        }
    }

    // END OWNER FUNCTIONS
    
}


