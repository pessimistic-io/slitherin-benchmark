//SPDX-License-Identifier: MIT
/*
*/

pragma solidity ^0.8.15;
import "./ERC20.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";


contract preSale is Ownable, ReentrancyGuard {

    ERC20 token;

    struct userInfo{
        bool isJoinPresale;
        uint256 amountFiat;
        address fiatAddressBuying;
        uint256 claimedAmount;
    }

    mapping(address => userInfo) public userInfoList;
    mapping(address => bool) public erc20Whitelist;
    uint256 price = 240; // 1u = 240
    uint256 public decimals;
    uint256 public startTimeClaim = 1683269955;
    constructor()
    {
        token = ERC20(0xB262E32Ae32dBB2dA6fc8E1B836Cb2e14Fab82b7);
        decimals = 10 ** token.decimals();
        erc20Whitelist[0x039c13B36a412d5a5eA750f7E563c1fD94272a1f] = true;
    }

    function editStartTimeClaimng(uint256 _startTimeClaim) external onlyOwner
    {
        startTimeClaim = _startTimeClaim;
    }

    function setERC20Whitelist(address[] calldata _address, bool _state) external onlyOwner
    {
        for(uint256 i = 0; i <= _address.length; i++)
        {
            erc20Whitelist[_address[i]] = _state;
        }
    }

    function buy(address _token, uint256 _fiatAmount) external
    {
        userInfo storage user = userInfoList[msg.sender];

        uint256 _tokenAmount = _calculateToken(_fiatAmount) ;

        require(token.balanceOf(address(this)) >= _tokenAmount);

        require(erc20Whitelist[_token], "Token is not whitelist");
        require(IERC20(_token).transferFrom(msg.sender, address(this), _fiatAmount), "Error transfer");

        user.isJoinPresale = true;
        user.amountFiat += _fiatAmount;
        user.fiatAddressBuying = _token;
        user.claimedAmount += _tokenAmount;
    }

    function _calculateToken(uint256 _amount) public view returns(uint256 _result)
    {
        _result = (_amount * price) / (1 * 10**6);
    }

    function userClaim(address _user) external view returns(uint256 _result)
    {
        userInfo storage user = userInfoList[_user];
        return(user.claimedAmount * decimals);
    }

    function claim() external
    {
        userInfo storage user = userInfoList[msg.sender];
        require(user.isJoinPresale, "You did not joined");
        require(token.transfer(msg.sender,user.claimedAmount), "Error transfer");
        user.isJoinPresale = false;
        user.claimedAmount = 0;
    }

    // amount BNB
    function withdrawNative(uint256 _amount) external onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require(address(this).balance >= _amount ,"balanceOfNative: is not enough");
        payable(msg.sender).transfer(_amount);
    }

    function withdrawToken(IERC20 _token, uint256 _amount) external onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require(_token.balanceOf(address(this)) >= _amount , "balanceOfToken:is not enough");
        _token.transfer(msg.sender, _amount);
    }

    // all BNB
    function withdrawNativeAll() external onlyOwner {
        require(address(this).balance > 0 ,"balanceOfNative: is equal 0");
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawTokenAll(IERC20 _token) external onlyOwner {
        require(_token.balanceOf(address(this)) > 0 , "balanceOfToken: is equal 0");
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

}
