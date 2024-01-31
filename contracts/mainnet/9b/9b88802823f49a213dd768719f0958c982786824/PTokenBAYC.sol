// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./PToken.sol";
import "./IApeStaking.sol";
import "./IPTokenBAKC.sol";

/**
 * @title Pawnfi's PTokenBAYC Contract
 * @author Pawnfi
 */
contract PTokenBAYC is PToken {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // bytes32(uint256(keccak256('eip1967.proxy.stakeDelegate')) - 1))
    bytes32 private constant _STAKE_DELEGATE_SLOT = 0xb8eef20a3eb5434ad680459d96ef6f313aea93fa19e616f4755d155d7b1b3810;

    /**
     * @notice set ApeStaking contract address
     * @param stakeDelegate ApeStaking address
     */
    function setStakeDelegate(address stakeDelegate) public virtual {
        require(IOwnable(factory).owner() == msg.sender, "Caller isn't owner");
        require(
            AddressUpgradeable.isContract(stakeDelegate),
            "PTokenBAKC: stakeDelegate is not a contract"
        );
        bytes32 slot = _STAKE_DELEGATE_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, stakeDelegate)
        }
    }

    /**
     * @notice get ApeStaking contract address
     * @return stakeDelegate ApeStaking address
     */
    function getStakeDelegate() public view virtual returns (address stakeDelegate) {
        bytes32 slot = _STAKE_DELEGATE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            stakeDelegate := sload(slot)
        }
    }

    /**
     * @notice get ApeCoinStaking contract address
     * @return address ApeCoinStaking address
     */
    function getApeCoinStaking() public view virtual returns (address) {
        return IApeStaking(getStakeDelegate()).apeCoinStaking();
    }

    /**
     * @notice get P-BAKC contract address
     * @return address P-BAKC address
     */
    function getPTokenBAKC() public view virtual returns (address) {
        return IApeStaking(getStakeDelegate()).pbakcAddr();
    }

    /**
     * @notice get nft id depositor
     * @param nftId nft id
     * @return address nft id depositor address
     */
    function getNftOwner(uint256 nftId) external view virtual returns(address) {
        return _allInfo[nftId].endBlock > 0 ? _allInfo[nftId].userAddr : address(0);
    }

    modifier onlyApeStaking() {
        require(msg.sender == getStakeDelegate(), "Caller is not stakeDelegate address");
        _;
    }

    /**
     * @notice approve amount to ApeCoinStaking contract
     * @param amount approve amount
     */
    function _approveMax(uint256 amount) internal {
        address apeCoinStaking = getApeCoinStaking();
        IERC20Upgradeable token = IERC20Upgradeable(IApeCoinStaking(apeCoinStaking).apeCoin());
        uint allowance = token.allowance(address(this), apeCoinStaking);
        if(allowance < amount) {
            token.approve(apeCoinStaking, 0);
            token.approve(apeCoinStaking, type(uint256).max);
        }
    }

    /**
     * @notice stake APE with single nft id list
     * @param amount stake APE amount
     * @param _nfts nft id list
     */
    function depositApeCoin(uint256 amount, IApeCoinStaking.SingleNft[] memory _nfts) external virtual onlyApeStaking {
        _approveMax(amount);
        IApeCoinStaking(getApeCoinStaking()).depositBAYC(_nfts);
    }

    /**
     * @notice claim APE with single nft id list
     * @param _nfts nft id list
     * @param recipient address to receive APE reward
     */
    function claimApeCoin(uint256[] calldata _nfts, address recipient) external virtual onlyApeStaking {
        IApeCoinStaking(getApeCoinStaking()).claimBAYC(_nfts, recipient);
    }

    /**
     * @notice withdraw APE with single nft id list
     * @param _nfts nft id list
     * @param recipient address to receive APE
     */
    function withdrawApeCoin(IApeCoinStaking.SingleNft[] calldata _nfts, address recipient) external virtual onlyApeStaking {
        IApeCoinStaking(getApeCoinStaking()).withdrawBAYC(_nfts, recipient);
    }

    /**
     * @notice stake APE with pair nft id list
     * @param amount stake APE amount
     * @param _nftPairs pair nft id list
     */
    function depositBAKC(uint256 amount, IApeCoinStaking.PairNftDepositWithAmount[] calldata _nftPairs) external virtual onlyApeStaking {
        _approveMax(amount);
        address ptoken = getPTokenBAKC();
        uint256 length = _nftPairs.length;
        uint256[] memory nftIds = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            nftIds[i] = _nftPairs[i].bakcTokenId;
        }

        bytes memory data = abi.encodeWithSelector(IApeCoinStaking.depositBAKC.selector, _nftPairs, new IApeCoinStaking.PairNftDepositWithAmount[](0));
        IPTokenBAKC(ptoken).flashLoan(address(this), nftIds, data);
        
    }

    /**
     * @notice claim APE with pair nft id list
     * @param _nftPairs pair nft id list
     * @param recipient address to receive APE reward
     */
    function claimBAKC(IApeCoinStaking.PairNft[] calldata _nftPairs, address recipient) external virtual onlyApeStaking {
        address ptoken = getPTokenBAKC();
        uint256 length = _nftPairs.length;
        uint256[] memory nftIds = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            nftIds[i] = _nftPairs[i].bakcTokenId;
        }

        bytes memory data = abi.encodeWithSelector(IApeCoinStaking.claimBAKC.selector, _nftPairs, new IApeCoinStaking.PairNftDepositWithAmount[](0), recipient);
        IPTokenBAKC(ptoken).flashLoan(address(this), nftIds, data);
    }

    /**
     * @notice withdraw APE with pair nft id list
     * @param _nftPairs pair nft id list
     * @param recipient address to receive APE
     */
    function withdrawBAKC(IApeCoinStaking.PairNftWithdrawWithAmount[] calldata _nftPairs, address recipient) external virtual onlyApeStaking {
        address ptoken = getPTokenBAKC();
        uint256 length = _nftPairs.length;
        uint256[] memory nftIds = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            nftIds[i] = _nftPairs[i].bakcTokenId;
        }

        bytes memory data = abi.encodeWithSelector(IApeCoinStaking.withdrawBAKC.selector, _nftPairs, new IApeCoinStaking.PairNftDepositWithAmount[](0));
        IPTokenBAKC(ptoken).flashLoan(address(this), nftIds, data);

        address apeCoin = IApeCoinStaking(getApeCoinStaking()).apeCoin();
        IERC20Upgradeable(apeCoin).transfer(recipient, IERC20Upgradeable(apeCoin).balanceOf(address(this)));
    }

    /**
     * @notice callback function，only supported by P-BAKC contract
     * @param nftIds nft id list
     * @param data callback data
     */
    function pTokenCall(uint256[] calldata nftIds, bytes memory data) external virtual {
        address ptoken = getPTokenBAKC();
        require(msg.sender == ptoken, "Caller is not P-BAKC address");
        getApeCoinStaking().functionCall(data);
        
        for(uint i = 0; i < nftIds.length; i++) {
            TransferHelper.approveNonFungibleToken(IPTokenFactory(factory).nftTransferManager(), IPToken(ptoken).nftAddress(), address(this), ptoken, nftIds[i]);
        }
    }

    /**
     * @dev See {PToken-specificTrade}.
     */
    function specificTrade(uint256[] memory nftIds) public virtual override {
        IApeStaking(getStakeDelegate()).onStopStake(msg.sender, nftAddress, nftIds, IApeStaking.RewardAction.ONREDEEM);
        super.specificTrade(nftIds);
    }

    /**
     * @dev See {PToken-withdraw}.
     */
    function withdraw(uint256[] memory nftIds) public virtual override returns (uint256 tokenAmount) {
        IApeStaking(getStakeDelegate()).onStopStake(msg.sender, nftAddress, nftIds, IApeStaking.RewardAction.ONWITHDRAW);
        return super.withdraw(nftIds);
    }

    /**
     * @dev See {PToken-convert}.
     */
    function convert(uint256[] memory nftIds) public virtual override {
        IApeStaking(getStakeDelegate()).onStopStake(msg.sender, nftAddress, nftIds, IApeStaking.RewardAction.ONWITHDRAW);
        super.convert(nftIds);
    }


}
