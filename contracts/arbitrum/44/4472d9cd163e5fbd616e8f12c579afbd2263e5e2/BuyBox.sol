// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Strings.sol";

import "./IAccessor.sol";
import "./SecurityBase.sol";


interface IToken {
    function balanceOf(address to) external returns (uint);
    function allowance(address owner, address spender) external returns (uint);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address owner, address to, uint amount) external;
}

contract BuyBox is SecurityBase   {

    IAccessor   public _accessor;
    string      public _header;
    bool        public _pending;
    uint        public _cursor;
    uint        public _tokenCnt;
    
    mapping(address => bool)    private _supportedTokens;
    mapping(address => uint)    private _priceList;
    mapping(string => bool)     private _usedNonces;
    mapping(address => uint)    private _stats;
    
    uint constant public ROUND = 1;
    uint constant public TOTAL_SUPPLY = 300;

    event Sent(string nonce, uint usedAmount);
    event Refund(string nonce , uint refundAmount, string reason);

    struct StatusContext {
        string state;
        uint round;
        uint totalSupply;
        uint cursor;
    }

    constructor(){
        _cursor = 0;
        _pending = true;

        // Pre-generated metadata header
        _header = _stringJoin(_stringJoin("A", _itos(ROUND-1)), "#A1#");
    }

    function setAccessor(address newValue) external onlyMinter {
        _accessor = IAccessor(newValue);
    }

    function registerToken(address newValue, uint price) external onlyMinter {
        require(price > 0, "wrong price");

        if (!_supportedTokens[newValue]) {
            _tokenCnt++;
            _priceList[newValue] = price;
            _supportedTokens[newValue] = true;
        }
    }

    function unregisterToken(address newValue) external onlyMinter {
        if (_supportedTokens[newValue]) {
            _tokenCnt--;
            delete _priceList[newValue];
            _supportedTokens[newValue] = false;
        }
    }

    function check() external view returns(bool, string memory) {
        return _check();
    }

    function open() external onlyMinter {
        (bool ok, string memory err) = _check();
        require(ok, err);

        if (_pending) {
            _pending = false;
        }
    }

    function status() external view returns(StatusContext memory) {
        StatusContext memory context;
        context.round = ROUND;
        context.totalSupply = TOTAL_SUPPLY;
        context.cursor = _cursor;
        if (_cursor >= TOTAL_SUPPLY) {
            context.state = "SELL OUT";
        } else if (_pending) {
            context.state = "COMING SOON";
        } else {
            context.state = "OPEN";
        }
        return context;
    }

    function peek(address owner) external view returns(uint) {
        return _stats[owner];
    }

    function buy(address spender, address token, uint amount, string memory nonce) external onlyMinter {
        uint price = _priceList[token];
        require(_supportedTokens[token], "wrong token");
        require(amount >= price, "wrong amount");

        require(bytes(nonce).length > 0, "wrong nonce");
        require(!_usedNonces[nonce], "nonce used" );
        _usedNonces[nonce] = true;

        if (paused()) {
             _transfer(token, spender, amount);
            emit Refund(nonce, amount, "paused");
            return;
        }

        if (_pending) {
             _transfer(token, spender, amount);
            emit Refund(nonce, amount, "coming soon");
            return;
        }

        if (_cursor >= TOTAL_SUPPLY) {
            _transfer(token, spender, amount);
            emit Refund(nonce, amount, "sell out");
            return;
        }

        uint cnt = amount / price;
        if (_cursor + cnt > TOTAL_SUPPLY) {
            cnt = TOTAL_SUPPLY - _cursor;
        }

        // Generate DNA list of blind boxes.
        string[] memory lstMetadatas = new string[](cnt);
        for (uint i=0; i<cnt; i++) {
            string memory newSeq = _stringPadding(_itos(_cursor), "0", 4);
            lstMetadatas[i] = _stringJoin(_header, newSeq);
            _cursor++;
        }

        uint usedAmount = cnt * price;
        uint refundAmount = amount - usedAmount;

        // Mint blind boxes to spender address
        _accessor.mintBatch(spender, cnt, lstMetadatas);
        _stats[spender] += cnt;
        emit Sent(nonce, usedAmount);

        // Refund of remaining
        if (refundAmount > 0) {
            _transfer(token, spender, refundAmount);
            emit Refund(nonce, refundAmount, "partially succ");
        }
    }

    function withdraw(address token, address to, uint amount) external onlyMinter {
        require(amount > 0, "wrong amount");
         _transfer(token, to, amount);
    }

    function _check() private view returns(bool, string memory) {
        if (_tokenCnt == 0) {
            return (false, "_tokenCnt is 0");
        }
        if (_accessor == IAccessor(address(0))) {
            return (false, "_accessor is nil");
        }
        if (!_accessor.hasRole(keccak256("MINTER_ROLE"), address(this))) {
            return (false, "not authorized");
        }
        return (true, "succ");
    }

    function _transfer(address token, address to, uint amount) private returns(bool) {
        require(_supportedTokens[token], "wrong token");
        return IToken(token).transfer(to, amount);
    }

    function _stringJoin(string memory _a, string memory _b) private pure returns (string memory) {
        return string(abi.encodePacked(_a, _b));
    }

    function _stringPadding(string memory _s, string memory _byte, uint _maxLen) private pure returns(string memory) {
        uint256 n = _maxLen - bytes(_s).length ;
        if (n > 0) {
            string memory buffer = "";
            for (uint256 i=0;i<n;i++) {
                buffer=_stringJoin(buffer,_byte);
            }
            return _stringJoin(buffer,_s);
        }
        return _s;
    }

    function _itos(uint _i) private pure returns (string memory) {
        return Strings.toString(_i);
    }
}

