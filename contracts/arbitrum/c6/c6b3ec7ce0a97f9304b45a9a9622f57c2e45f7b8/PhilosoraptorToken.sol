//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20Snapshot.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract PhilosoraptorToken is Ownable, ERC20Snapshot {
    using SafeMath for uint256;
    address public uniswapV2Pair;
    address public treasury;
    uint256 public sellFeeRate = 2; // 2% fee to Treasury

    address public daoAddress;

    constructor(address _treasury) ERC20("Philosoraptor Token", "RAPTOR") {
        treasury = _treasury;
        _mint(msg.sender, 500000000000000 ether);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function getDAOAddress() public view returns(address){
        return daoAddress;
    }

    function setDAOAddress(address _address) external onlyOwner{
        daoAddress = _address;
    }

    function setUniswapV2Pair(address _address) external onlyOwner{
        uniswapV2Pair = _address;
    }

    function snapshot() external returns (uint256) {
        require(msg.sender == daoAddress, "!daoAddress");
        return _snapshot();
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        uint256 transferFeeRate = (recipient == uniswapV2Pair) ? sellFeeRate : 0;

        if(transferFeeRate > 0 && sender != address(this) && recipient != address(this)) {
            uint256 _fee = amount.mul(transferFeeRate).div(100);
            super._transfer(sender, treasury, _fee);
            amount = amount.sub(_fee);
        }
        super._transfer(sender, recipient, amount);
    }
}

