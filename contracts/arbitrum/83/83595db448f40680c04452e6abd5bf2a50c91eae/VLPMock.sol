// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IVault.sol";
import "./ERC20.sol";

contract VLPMock is IVault, ERC20 {
    //6 decemial;
    uint256 public VlpPrice = 1_00_000;
    IERC20 usdcToken;

    constructor(address _usdc) ERC20("mVLP Token", "mVLP") {
        _mint(msg.sender, 10000 * (10 ** decimals()));
        usdcToken = IERC20(_usdc); // mint initial supply to contract deployer
    }

    function stake(address account, address _token, uint256 usdcAmount) external {
        usdcToken.transferFrom(account, address(this), usdcAmount);

        uint256 mintAmount = (usdcAmount * 1e18) / (getVLPPrice() * 10);

        _mint(account, mintAmount);
    }

    function unstake(address _tokenOut, uint256 _vlpAmount, address _receiver) external {
        usdcToken.transfer(_receiver, ((_vlpAmount * (getVLPPrice() * 10)) / 1e18));

        _burn(_receiver, _vlpAmount);
    }

    function setVLPPrice(uint256 newPrice) external returns (uint256) {
        VlpPrice = newPrice;
        return newPrice;
    }

    function getVLPPrice() public view returns (uint256) {
        return VlpPrice;
    }
}

