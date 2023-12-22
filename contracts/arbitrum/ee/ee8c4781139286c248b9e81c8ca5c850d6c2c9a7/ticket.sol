// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./InPersonTicketNFT.sol";

contract Ticket is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public gohm;
    IERC20 public frax;
    IERC20 public dai;
    mapping(string => uint256) public usdTicketPrices;
    mapping(string => uint256) public gohmTicketPrices;
    string[] public ticketTypes;
    address public gnosisMultiSigAddr;
    address public inPersonTicketNFTAddr;
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event WithdrawFundTo(
        address indexed gnosisMultiSigAddr,
        uint256 tokenIdx,
        uint256 tokenBalance
    );

    constructor(
        address multisig,
        address nftAddr,
        address gohmAddr,
        address fraxAddr,
        address daiAddr
    ) {
        gohm = IERC20(gohmAddr);
        frax = IERC20(fraxAddr);
        dai = IERC20(daiAddr);
        gnosisMultiSigAddr = multisig;
        inPersonTicketNFTAddr = nftAddr;
    }

    // Modifier to check token allowance
    modifier checkAllowance(
        string memory tokenName,
        string memory ticketName,
        bool isStableCoin
    ) {
        uint256 tokenPrice = _getTicketPrice(
            ticketName,
            isStableCoin
        );
        IERC20 _token = _getTokenIERCbyName(tokenName);
        emit Approval(msg.sender, address(this), tokenPrice);
        require(
            _token.allowance(msg.sender, address(this)) >= tokenPrice,
            "Error"
        );
        _;
    }

    function setTicketPrice(
        string memory ticketName,
        bool isStableCoin,
        uint256 ticketPrice
    ) public onlyOwner {
        if (isStableCoin == true) {
            usdTicketPrices[ticketName] = ticketPrice;
        }
        gohmTicketPrices[ticketName] = ticketPrice;
    }

    function setInPersonTicketNFTAddr(address addr) public onlyOwner {
        inPersonTicketNFTAddr = addr;
    }

    function buyTicket(
        string memory tokenName,
        string memory ticketName,
        bool isStableCoin
    ) public checkAllowance(tokenName, ticketName, isStableCoin) {
        uint256 tokenPrice = _getTicketPrice(
            ticketName,
            isStableCoin
        );
        IERC20 token = _getTokenIERCbyName(tokenName);
        SafeERC20.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            tokenPrice
        );
        InPersonTicketNFT(inPersonTicketNFTAddr).mintNFT(msg.sender);
    }

    function withdrawToken() external onlyOwner {
        // multi-sig: Gnosis wallet address
        IERC20[3] memory tokenArray = [gohm, frax, dai];
        for (uint256 idx = 0; idx < tokenArray.length; idx++) {
            uint256 tokenBalance = tokenArray[idx].balanceOf(address(this));
            if (tokenBalance != 0) {
                tokenArray[idx].safeTransfer(gnosisMultiSigAddr, tokenBalance);
                emit WithdrawFundTo(gnosisMultiSigAddr, idx, tokenBalance);
            }
        }
    }

    function _getTokenIERCbyName(string memory tokenName)
        private
        view
        returns (IERC20)
    {
        if (
            keccak256(abi.encodePacked("gohm")) ==
            keccak256(abi.encodePacked(tokenName))
        ) {
            return gohm;
        } else if (
            keccak256(abi.encodePacked("frax")) ==
            keccak256(abi.encodePacked(tokenName))
        ) {
            return frax;
        } else if (
            keccak256(abi.encodePacked("dai")) ==
            keccak256(abi.encodePacked(tokenName))
        ) {
            return dai;
        }
        revert(
            "Invalid tokenName, it should be one of gohm, usdt, frax, dai"
        );
    }

    function _getTicketPrice(
        string memory ticketName,
        bool isStableCoin
    ) private view returns (uint256) {
        if (isStableCoin == true) {
            return
                usdTicketPrices[ticketName];
        }
        return gohmTicketPrices[ticketName];
    }
}
