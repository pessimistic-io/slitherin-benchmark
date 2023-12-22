// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";

contract ShipePresale is Ownable {

    event SetMinContribution(uint256 _minContribution);
    event SetMaxContribution(uint256 _maxContribution);
    event SetTeamWallet(address _teamWallet);
    event Contribute(address contributor, uint256 usdcAmount, uint256 tokenAmount);
    event Withdraw(address receiver, address token, uint256 amount);

    IERC20 public usdcToken;
    address public teamWallet;

    uint256 public constant DENO = 6;
    uint256 public constant seedSalePrice = 8000; // $0.008

    uint256 public totalUsdcAmount = 0;
    uint256 public totalTokenAmount = 0;

    uint256 public hardcap = 5000000 * 10 ** 18;

    uint256 public minContribution = 500 * 10 ** DENO;
    uint256 public maxContribution = 2500 * 10 ** DENO;

    uint256 public isStarted = 0;
    
    struct CONTRIBUTOR {
        uint256 tokenAmount;
        uint256 usdcAmount;
    }

    mapping (address => CONTRIBUTOR) public contributors;

    constructor(address _usdc) {
        usdcToken = IERC20(_usdc);
        isStarted = 0;
        teamWallet = 0x2B669CD93055d8a48D1Dc4103592eb10a58659eA;
    }

    function setSaleStart(uint256 _started) external onlyOwner {
        isStarted = _started;
    }

    function setHardcap(uint256 _hardcap) external onlyOwner {
        hardcap = _hardcap;
    }

    function setMinContribution(uint256 _minContribution) external onlyOwner {
        minContribution = _minContribution;
        emit SetMinContribution(_minContribution);
    }

    function setMaxContribution(uint256 _maxContribution) external onlyOwner {
        maxContribution = _maxContribution;
        emit SetMaxContribution(_maxContribution);
    }

    function setTeamWallet(address _team) external onlyOwner {
        teamWallet = _team;
        emit SetTeamWallet(_team);
    }

    function getContributableAmount(address _user) external view returns (uint256) {
        return maxContribution - contributors[_user].usdcAmount;
    }

    function contribute(uint256 _usdcAmount) external {
        require(isStarted == 1, "ShipePresale: Not presale period");
        address user = msg.sender;
        CONTRIBUTOR storage _contributor = contributors[user];
        require(_usdcAmount >= minContribution, "ShipePresale: Should be deposit more than minContribution = 1000");
        require(_contributor.usdcAmount + _usdcAmount <= maxContribution, "ShipePresale: Should be deposit less than maxContribution = 5000");
        
        uint256 _tokenAmount = 0;
        _tokenAmount = _usdcAmount / seedSalePrice * 10 ** 18;

        require(totalTokenAmount + _tokenAmount <= hardcap, "ShipePresale: Presale has finished");
        // Receive USDC to the contract
        usdcToken.transferFrom(user, teamWallet, _usdcAmount);
        _contributor.usdcAmount = _contributor.usdcAmount + _usdcAmount;
        _contributor.tokenAmount = _contributor.tokenAmount + _tokenAmount;

        totalUsdcAmount = totalUsdcAmount + _usdcAmount;
        totalTokenAmount = totalTokenAmount + _tokenAmount;

        emit Contribute(user, _usdcAmount, _tokenAmount);
    }

    function withdraw(address to, address token) external onlyOwner {
        uint256 _amount;
        if (token == address(0)) {
            _amount = address(this).balance;
            require(_amount > 0, "No ETH to withdraw");

            (bool success, ) = payable(to).call{value: _amount}("");
            require(success, "Unable to withdraw");
        } else {
            _amount = IERC20(token).balanceOf(address(this));
            require (_amount > 0, "Nothing to withdraw");
            bool success = IERC20(token).transfer(to, _amount);
            require(success, "Unable to withdraw");
        }

        emit Withdraw(to, token, _amount);
    }

    receive() payable external {}
    fallback() payable external {}
}
