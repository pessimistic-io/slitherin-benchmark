// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

interface IFee {
    function payFee(
        uint256 _tokenType
    ) external payable;
}
contract SimpleToken is ERC20, Ownable {
    using SafeERC20 for IERC20;
    IFee public constant feeContract = IFee(0xeabf9358872a8f313413D500A0293c2eCc085508);
    uint8 private _decimals;
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 __decimals,
        uint256 _totalSupply
    ) ERC20(_name, _symbol) payable {
        feeContract.payFee{value: msg.value}(0);   
        _decimals=__decimals;
        _mint(msg.sender, _totalSupply);
    }
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    function withdrawETH() external onlyOwner {
        (bool success, )=address(owner()).call{value: address(this).balance}("");
        require(success, "Failed in withdrawal");
    }
    function withdrawToken(address token) external onlyOwner{
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
