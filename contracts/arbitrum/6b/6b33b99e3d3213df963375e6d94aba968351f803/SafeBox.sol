pragma solidity ^0.5.16;

import "./Initializable.sol";
import "./SafeERC20.sol";

import "./ProxyOwned.sol";
import "./ProxyPausable.sol";

contract SafeBox is ProxyOwned, Initializable {
    using SafeERC20 for IERC20;
    IERC20 public sUSD;

    function initialize(address _owner, IERC20 _sUSD) public initializer {
        setOwner(_owner);
        sUSD = _sUSD;
    }

    function retrieveSUSDAmount(address payable account, uint amount) external onlyOwner {
        sUSD.transfer(account, amount);
    }
}

