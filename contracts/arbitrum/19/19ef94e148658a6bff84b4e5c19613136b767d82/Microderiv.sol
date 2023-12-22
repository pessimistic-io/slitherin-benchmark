// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./Math.sol";
import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";





interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

enum _State {Quote, Open, Closed}

struct c{ // contract
    uint256 id;
    address p_A; // long
    address p_B; // short
    uint256 oracle;
    address referral_address;
    address initiator;
    uint256 price;
    uint256 qty;
    uint256 im_A; // in % of notional
    uint256 im_B;
    uint256 df_A;
    uint256 df_B;
    uint256 ir;
    uint256 exp_A;//5min
    uint256 exp_B;//6month
    uint256 fee; // % of notional
    uint256 t0; // openTime
    _State state;
}

struct q{ // exit quote
    uint256 q_id; // quote id
    uint256 id; // contract id
    uint256 price; // limit price
    uint256 expiration; //timestamp
    address initiator; 
}

struct p{
    uint256 id;
    address price_feed;
    uint256 last_price;
    uint256 timestamp;
    address rescue_oracle;
    uint256 max_delay;
    //address provider_contract; //for custom methods
}


contract Microderiv {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public microderiv;  

    constructor(address _token_address, address _microderiv)  {
        token = IERC20(_token_address);
        microderiv = _microderiv;
    }

    mapping(address => uint256) public b; // account balances
    mapping(uint256 => p) public pM; // price feed
    uint256 pL; // price feed length
    mapping(uint256 => c) private cM; // contractsMap
    uint256 cL; // contractsMapLength
    mapping(uint256 => q) private qM; // quotesMap
    uint256 qL;  // quotesMapLength

    function deployPriceFeed(address a1, address a2, uint256 u1, uint256 u2) public {
        p memory newPriceFeed = p(
            pL, // id
            a1, // price_feed
            u1, // price
            block.timestamp, // timestamp
            a2,// rescue_oracle\
            u2
            //a4  provider_contract
            //TODO, add max price feed delay when using it
        );
        pM[pL] = newPriceFeed;
        pL++;
        emit DeployPriceFeed(pL, msg.sender);
    }
    event DeployPriceFeed(uint256 indexed p_id, address indexed _initiator);


    function updatePrice( uint256 p_id ) private {

        (,int price,,,) = AggregatorV3Interface(pM[p_id].price_feed).latestRoundData();
        pM[p_id].last_price = uint256(price);
        pM[p_id].timestamp = block.timestamp;

    }
    

    function deposit(uint256 _amount) public {
        require(_amount > 0, "Deposit amount must be greater than 0");
        token.safeTransferFrom(msg.sender, address(this), _amount);
        b[msg.sender] += _amount;

        emit Deposit(msg.sender, _amount);
    }

    function balanceOf(address account) public view returns (uint256) {
        return b[account];
    }

    function withdraw(uint256 _amount) public {
        require(b[msg.sender] >= _amount, "Insufficient balance");
        b[msg.sender] -= _amount;
        token.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    
    function _transfer(address _to, uint256 _value) public{
        require(b[msg.sender] >= _value);
        b[msg.sender] -= _value;
        b[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
    } 

    function quote(
        address[4] memory _address,
        uint256[11] memory _uint256
    ) public {
        c memory newContract = c(
            cL,  // id
            _address[0],  // p_A
            _address[1],  // p_B
            _uint256[10],  // chainlink price_feed here
            _address[3],  // referral_address
            msg.sender,  // initiator
            _uint256[0],  // price
            _uint256[1],  // quantity
            _uint256[2],  // im_A
            _uint256[3],  // im_B
            _uint256[4],  // df_A
            _uint256[5],  // df_B
            _uint256[6],  // ir
            _uint256[7],  // exp_A
            _uint256[8],  // exp_B
            _uint256[9], // fee
            block.timestamp, // openTime (current block timestamp)
            _State.Quote // state 
        );
        
        
        if ( b[msg.sender] > _uint256[2] + _uint256[2] + _uint256[9] && msg.sender == _address[0] ){
            require( b[msg.sender] > _uint256[2] + _uint256[2] + _uint256[9] );
            b[msg.sender] -= (_uint256[2] + _uint256[4] + _uint256[9]);
        } else if ( b[msg.sender] > _uint256[3] + _uint256[5] + _uint256[9] && msg.sender == _address[1] ){
            require( b[msg.sender] > _uint256[3] + _uint256[5] + _uint256[9] );
            b[msg.sender] -= (_uint256[3] + _uint256[5] + _uint256[9]);
        }
        cL++;
        cM[cL] = newContract;
        emit Quote(cL, msg.sender);
    }

    function acceptQuote(uint256 _id) public {
        if (msg.sender == cM[_id].p_B && cM[_id].initiator == cM[_id].p_A){
            if (cM[_id].state == _State.Quote && b[msg.sender] > (cM[_id].im_B + cM[_id].df_B)){ 
                b[cM[_id].p_A] = b[cM[_id].p_A] - cM[_id].im_A - cM[_id].df_A + ( cM[_id].fee / 2);
                cM[_id].state = _State.Open;
            }
        }
        
        if (msg.sender == cM[_id].p_A && cM[_id].initiator == cM[_id].p_B){
            if (cM[_id].state == _State.Quote && b[msg.sender] > (cM[_id].im_A + cM[_id].df_A)){
                b[cM[_id].p_B] = b[cM[_id].p_B] - cM[_id].im_B - cM[_id].df_B + cM[_id].fee;
                cM[_id].state = _State.Open;
            }
        }

        b[cM[_id].referral_address] = ( cM[_id].fee * 7 /20);
        b[microderiv] = ( cM[_id].fee * 3 / 20);
        cM[_id].state = _State.Open;
        emit AcceptQuote(_id, msg.sender);
    }


    function closeQuote( uint[3] memory u, address initiator)public{
        if ((initiator == cM[u[0]].p_A || initiator == cM[u[0]].p_A) 
                && cM[u[0]].state == _State.Open 
                && ( msg.sender== cM[u[0]].p_A || msg.sender == cM[u[0]].p_B)){
            q memory newQuote = q(
                qL, // q_id
                u[0], // id
                u[1], // price
                u[2], // expiration
                initiator // initiator
            );
            qM[qL] = newQuote;
            qL++;
            emit CloseQuote(qL, initiator);
        }
    }

    function acceptClose( uint256 q_id ) public {
        if (qM[q_id].initiator == cM[qM[q_id].id].p_A ) {
            require( msg.sender == cM[qM[q_id].id].p_B);
        } else if (qM[q_id].initiator == cM[qM[q_id].id].p_B ){
            require( msg.sender == cM[qM[q_id].id].p_A);
        }
        require( block.timestamp < qM[q_id].expiration);
        (uint256 uPnL_A,uint256 uPnL_B) = uPnL(qM[q_id].id, qM[q_id].price);
        closePosition(qM[q_id].id, uPnL_A, uPnL_B);
        emit AcceptClose(q_id, msg.sender);
    }

    function closeMarket( uint256 c_id, uint256 max_delay ) public{
        require( cM[c_id].state == _State.Open);
        require(block.timestamp - pM[cM[c_id].oracle].timestamp > max_delay, "Price feed delay" );
        uint256 price = pM[cM[c_id].oracle].last_price;
        (uint256 uPnL_A,uint256 uPnL_B) = uPnL(c_id, price);
        if (msg.sender == cM[c_id].p_A){
            if (block.timestamp < cM[c_id].exp_A || uPnL_A < cM[c_id].im_A){
                b[cM[c_id].p_B] += cM[c_id].df_A * 9/10 ;
                b[microderiv] += cM[c_id].df_A * 1/20;
                b[cM[c_id].referral_address] += cM[c_id].df_A * 1/20;
                closePosition(c_id, uPnL_A, uPnL_B);
            } else {
                closePosition(c_id, uPnL_A, uPnL_B);
            }
        }
            if (msg.sender == cM[c_id].p_B) {
                if (block.timestamp < cM[c_id].exp_A || uPnL_B < cM[c_id].im_B) {
                    b[cM[c_id].p_A] += cM[c_id].df_B * 9/10;
                    b[microderiv] += cM[c_id].df_B * 1/20;
                    b[cM[c_id].referral_address] += cM[c_id].df_B * 1/20;
                    closePosition(c_id, uPnL_A, uPnL_B);
                } else {
                    closePosition(c_id, uPnL_A, uPnL_B);
                }
            }
            emit CloseMarket(c_id, msg.sender);
        }
    
    

    function liquidate( uint256 c_id )public{
        require( cM[c_id].state == _State.Open);
        require(block.timestamp - pM[cM[c_id].oracle].timestamp > pM[cM[c_id].oracle].max_delay, "Price feed delay" );
        uint256 price = pM[cM[c_id].oracle].last_price;
        (uint256 uPnL_A,uint256 uPnL_B) = uPnL(c_id, price);
        if ( uPnL_A > cM[c_id].im_A ) {
            if (b[cM[c_id].p_A] > uPnL_A - cM[c_id].im_A ){
                b[cM[c_id].p_A] -= uPnL_A;
                b[cM[c_id].p_B] += uPnL_B;
            } else {
                uint256 _liquidatorFee = cM[c_id].df_A / 10;
                b[cM[c_id].p_A] = 0 ;
                b[cM[c_id].p_B] += cM[c_id].im_A + ( cM[c_id].df_A * 8/10  ) + b[cM[c_id].p_A] - _liquidatorFee;
                b[microderiv] += cM[c_id].df_A * 1/20;
                b[cM[c_id].referral_address] += cM[c_id].df_A * 1/20;
                b[msg.sender] += _liquidatorFee;
            }
        }
        if ( uPnL_B > cM[c_id].im_B ) {
            if (b[cM[c_id].p_B] > uPnL_B - cM[c_id].im_B) {
                b[cM[c_id].p_B] -= uPnL_B;
                b[cM[c_id].p_A] += uPnL_A;
            } else {
                uint256 _liquidatorFee = cM[c_id].df_B / 10;
                b[cM[c_id].p_B] = 0 ;
                b[cM[c_id].p_A] += cM[c_id].im_B + ( cM[c_id].df_B * 8/10 ) + b[cM[c_id].p_B] - _liquidatorFee;
                b[microderiv] += cM[c_id].df_B * 1/20;
                b[cM[c_id].referral_address] += cM[c_id].df_B * 1/20;
                b[msg.sender] += _liquidatorFee;
            }
        }
        cM[c_id].state = _State.Closed;
        emit Liquidate(c_id, msg.sender);
    }
    

    //do not handle liquidations
    function settlement(uint256 c_id)public{
        require( cM[c_id].state == _State.Open);
        require(block.timestamp - pM[cM[c_id].oracle].timestamp > pM[cM[c_id].oracle].max_delay, "Price feed delay" );
        uint256 price = pM[cM[c_id].oracle].last_price;
        (uint256 uPnL_A,uint256 uPnL_B) = uPnL(c_id, price);
        if (uPnL_A > 0) {
            b[cM[c_id].p_A] += uPnL_A;
            b[cM[c_id].p_B] -= uPnL_B;
        } else {
            b[cM[c_id].p_A] -= uPnL_A;
            b[cM[c_id].p_B] += uPnL_B;
        }
        cM[c_id].price = price;
        cM[c_id].t0 = block.timestamp;
        emit Settlement(c_id, msg.sender);
    }

    function cancelQuote( uint256 c_id ) public{
        require(cM[c_id].initiator == msg.sender && cM[c_id].state == _State.Quote);
        cM[c_id].state = _State.Closed;
        if (cM[c_id].initiator == cM[c_id].p_A) {
            b[cM[c_id].initiator] += cM[c_id].im_A + cM[c_id].df_A + ( cM[c_id].fee );
        } else {
            b[cM[c_id].initiator] += cM[c_id].im_B + cM[c_id].df_B + ( cM[c_id].fee );
        }
        emit CancelClose(c_id, msg.sender);
    }

    function cancelClose( uint256 q_id )public{
        require(qM[q_id].initiator == msg.sender);
        qM[q_id].expiration = block.timestamp;
        emit CancelClose(q_id, msg.sender);
    }

    function closePosition( uint256 c_id, uint256 uPnL_A, uint256 uPnL_B) private{
        if (uPnL_A > uPnL_B) {
            uint256 pnl = min(uPnL_A - uPnL_B, cM[c_id].im_B);
            b[cM[c_id].p_A] += pnl;
            b[cM[c_id].p_B] -= pnl;
        } else {
            uint256 pnl = min(uPnL_B - uPnL_A, cM[c_id].im_A);
            b[cM[c_id].p_A] -= pnl;
            b[cM[c_id].p_B] += pnl;
        }
        cM[c_id].state = _State.Closed;
    }

    //return only earnings ammount
    function uPnL( uint256 c_id, uint256 price) private view returns (uint256, uint256) {
        uint256 ir =cM[c_id].ir * ( block.timestamp - cM[c_id].t0) * cM[c_id].qty / 31536000;
        uint256 uPnL_A;
        uint256 uPnL_B;

        if (cM[c_id].initiator == cM[c_id].p_A) {
            uPnL_B = ir;
        } else {
            uPnL_A = ir;
        }

        if (price < cM[c_id].price) {
            uPnL_B = (cM[c_id].price - price) * cM[c_id].qty;
        } else {
            uPnL_A = (price - cM[c_id].price) * cM[c_id].qty;
        }
        
        if (uPnL_A > uPnL_B) {
            uPnL_A -= uPnL_B;
            uPnL_B = 0;
        } else {
            uPnL_B -= uPnL_A;
            uPnL_A = 0;
        }

        return (uPnL_A, uPnL_B);
    }

    function min(uint256 x, uint256 y) public pure returns (uint256) {
        return x > y ? x : y;
    }

    function getBalance(address _address) public view returns (uint256){
        return b[_address];
    }

    function getPositionPart1(uint256 _id) public view returns (
        uint256, address, address, uint256, address, address, uint256, uint256, uint256, uint256
    ) {
        c storage contract_ = cM[_id];
        return (
        contract_.id,
        contract_.p_A,
        contract_.p_B,
        contract_.oracle,
        contract_.referral_address,
        contract_.initiator,
        contract_.price,
        contract_.qty,
        contract_.im_A,
        contract_.im_B
        );
    }

    function getPositionPart2(uint256 _id) public view returns (
        uint256, uint256, uint256, uint256, uint256, uint256, _State
    ) {
        c storage contract_ = cM[_id];
        return (
        contract_.df_A,
        contract_.df_B,
        contract_.ir,
        contract_.exp_A,
        contract_.exp_B,
        contract_.t0,
        contract_.state
        );
    }

    function getQuote(uint256 _id) public view returns (
        uint256, uint256, uint256, uint256, address
    ) {
        q storage _quote = qM[_id];
        return (
        _quote.q_id,
        _quote.id,
        _quote.price,
        _quote.expiration,
        _quote.initiator
        );
    }

    event Deposit(address indexed _from, uint256 _value);
    event Withdraw(address indexed _to, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Quote(uint256 indexed _id, address indexed _initiator);
    event AcceptClose(uint256 indexed _id, address indexed _initiator); 
    event AcceptQuote(uint256 indexed _id, address indexed _initiator);
    event CloseQuote(uint256 indexed _id, address indexed _initiator);
    event CloseMarket(uint256 indexed _id, address indexed _initiator);
    event Liquidate(uint256 indexed _id, address indexed _initiator);
    event Settlement(uint256 indexed _id, address indexed _initiator);
    event CancelClose(uint256 indexed _id, address indexed _initiator);
    event CancelQuote(uint256 indexed _id, address indexed _initiator);
}

