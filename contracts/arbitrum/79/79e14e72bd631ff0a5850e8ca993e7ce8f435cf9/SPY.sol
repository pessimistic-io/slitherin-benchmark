// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./ERC20.sol";
import "./SafeMath.sol";

contract SPY is ERC20 {
    address gov;
    using SafeMath for uint256;
    uint256 public MAX_SUPPLY = 6000000 * 10 ** decimals(); // 6,000,000

    mapping (address => bool) public isMinter;
    mapping (address => bool) public isHandler;

    constructor() ERC20("Sympathy Finance", "SPY") {
        gov = _msgSender();
    }

    modifier onlyGov() {
        require(gov == _msgSender(), "MintalbeERC20: forbidden");
        _;
    }
    
    modifier onlyMinter() {
        require(isMinter[_msgSender()], "MintalbeERC20: forbidden");
        _;
    }

    function setMinter(address _minter, bool _isActive) external onlyGov {
        require(_minter != address(0), "SPY: invalid address");
        isMinter[_minter] = _isActive;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        require(_handler != address(0), "SPY: invalid address");
        isHandler[_handler] = _isActive;
    }

    function setHandlers(address[] memory _handler, bool[] memory _isActive) external onlyGov {
        for(uint256 i = 0; i < _handler.length; i++){
            isHandler[_handler[i]] = _isActive[i];
        }
    }

    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "SPY: invalid address");
        
        require(totalSupply().add(amount) <= MAX_SUPPLY, "SPY::max total supply");
        _mint(to, amount);
    }

    function burn(address _account, uint256 _amount) external onlyMinter {
        _burn(_account, _amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();

        if (isHandler[spender]) {
            _transfer(from, to, amount);
            return true;
        }

        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // no need to correspond with want decimals
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

