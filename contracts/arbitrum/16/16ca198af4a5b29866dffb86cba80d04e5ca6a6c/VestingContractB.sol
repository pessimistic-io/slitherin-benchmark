/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC20BackwardsCompatible.sol";

contract VestingContractB is Ownable, ReentrancyGuard {
    address public immutable ARC;
    IERC20 public immutable arc;

    mapping (address => uint256) public ethAmount;
    mapping (address => mapping (uint256 => bool)) public claims;
    mapping (address => uint256) public claimedTokens;
    uint256 public ethTotal = 100 ether;
    uint256 public start;

    constructor (address _ARC) {
        ARC = _ARC;
        arc = IERC20(_ARC);

        ethAmount[0xf73305245afE0cBb1E64B0E0941CFF5eB6dA0194] = 5 ether;
        ethAmount[0x42b6229E536c01aEb20922D3DeC5af1c0a8585c9] = 5 ether;
        ethAmount[0x2DFe63c5c02805d94Fa1e5204e30ba82d76174a3] = 5 ether;
        ethAmount[0x7b5EdceC8DE439290c3D314411393b8174e93F98] = 5 ether;
        ethAmount[0xf5F14b4C229770Ac5FD948a32eCFD3Ba6Abb6Ff4] = 5 ether;
        ethAmount[0x9a1EaBb4cFe6fC4b624B2b84D917B1453c5fe8bb] = 5 ether;
        ethAmount[0x6a1617a5E98d7540557044f3C88BE6c4266f1e15] = 5 ether;
        ethAmount[0x3e1f15E9994387E4FE3E45B34076c8d25Cd7D2a4] = 5 ether;
        ethAmount[0x950D2d8761b70E1E4F3ECeBAc9bE1dBBCeA75d43] = 5 ether;
        ethAmount[0xaB650fbC2AB9A71045A7DEd344ae5E8803ee3E1b] = 5 ether;
        ethAmount[0x4D05651cB4E0834Ddfe0987e998baC151263D2E3] = 2.6 ether;
        ethAmount[0xC0e2278ACEc087B57E1030e929CD04cf6A168F82] = 2.6 ether;
        ethAmount[0xBa42828d289d964AcF7d3Bc67c35F19C8d53A5fa] = 2.6 ether;
        ethAmount[0xdCc3CC686f0835837B83DdA591fb84F8817A7b0A] = 2.6 ether;
        ethAmount[0xb7048f1C846a3b49d126166bB7699ac31fd97382] = 2.6 ether;
        ethAmount[0xd3896A9005998C54D6F3BD997286FDcA7030Ac37] = 2.6 ether;
        ethAmount[0x4b65dd7D001070099d5c8f1Fa1e2937FceD480aC] = 2.6 ether;
        ethAmount[0x3c843dD872C95253a76A50300528c295D74ADac9] = 2.6 ether;
        ethAmount[0x6676E2110335c9698AAAf2190563F127a658ed77] = 2.6 ether;
        ethAmount[0xA332CD3c6b686e20a2a1CF2a13Cb67b895e01A5b] = 2.6 ether;
        ethAmount[0x784941B0cA053Aab18E119a646E7F4761530CbAc] = 2.6 ether;
        ethAmount[0x65e1906Ce38A55CB48860a2407a0C017C09aBD42] = 2.6 ether;
        ethAmount[0xD85A6DFB505a76d272cAF51af79F55d929469D68] = 2.6 ether;
        ethAmount[0xFF82f712B12d428659AFB4c8739cc8bec4a1B55b] = 2.6 ether;
        ethAmount[0x12E9a397d23B7EA5B4C00376BF923CFb31f22458] = 2.6 ether;
        ethAmount[0x7b9eBe4f789E53bB12c314ca4f144092FEeE152b] = 2.4 ether;
        ethAmount[0x51c64cAFA40f49f442461D325E3B182B3eF17Cae] = 2.4 ether;
        ethAmount[0x19F4762e5688E46711204f766F2D1F65A560c993] = 2.4 ether;
        ethAmount[0x37eFE342918b4FCA9c9d286C74B5CAE968740418] = 2.4 ether;
        ethAmount[0x82F8f2cFFD0A68D08B4d5d4da01d55B7069A3106] = 2.4 ether;
        start = block.timestamp;
    }

    function getTokensPerAccount(address _account) public view returns (uint256) {
        if (ethAmount[_account] == 0) {
            return 0;
        }
        return (2000000 * (10**18)) * ethAmount[_account] / ethTotal;
    }

    function getClaimsByAccount(address _account) external view returns (uint256) {
        return claimedTokens[_account];
    }

    function claim() external nonReentrant {
        uint256 _tokens;
        if ((block.timestamp >= start) && (!claims[msg.sender][0])) {
            _tokens += getTokensPerAccount(msg.sender) * 3100 / 10000;
            claimedTokens[msg.sender] += _tokens;
            claims[msg.sender][0] = true;
        }
        if ((block.timestamp >= start + (86400 * 7)) && (!claims[msg.sender][1])) {
            _tokens += getTokensPerAccount(msg.sender) * 2300 / 10000;
            claimedTokens[msg.sender] += _tokens;
            claims[msg.sender][1] = true;
        }
        if ((block.timestamp >= start + (86400 * 14)) && (!claims[msg.sender][2])) {
            _tokens += getTokensPerAccount(msg.sender) * 2300 / 10000;
            claimedTokens[msg.sender] += _tokens;
            claims[msg.sender][2] = true;
        }
        if ((block.timestamp >= start + (86400 * 21)) && (!claims[msg.sender][3])) {
            _tokens += getTokensPerAccount(msg.sender) * 2300 / 10000;
            claimedTokens[msg.sender] += _tokens;
            claims[msg.sender][3] = true;
        }
        if (_tokens > 0) {
            arc.transfer(msg.sender, _tokens);
        }
    }

    function emergencyWithdrawToken(address _token, uint256 _amount) external nonReentrant onlyOwner {
        IERC20BackwardsCompatible(_token).transfer(msg.sender, _amount);
    }

    function emergencyWithdrawETH(uint256 _amount) external nonReentrant onlyOwner {
        payable(msg.sender).call{value: _amount}("");
    }

    receive() external payable {}
}

