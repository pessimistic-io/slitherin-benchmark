// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ERC20.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./StructLibrary.sol";
import "./InterfaceLibrary.sol";

contract CollectionContract is Ownable {

    address public factory;
    mapping (address => Socials) socials; 

    event DeployCollection(address indexed deployer);
    event SetCollectionInfo(address indexed account);

    constructor(
        address _factory
    ) {
        factory = _factory;
    }

    function allowedCollections() public view returns (uint256[] memory col) {

        uint256 counter = 0;       
        int256[] memory c = new int256[](IFactory(factory).totalDeployed());

        for (uint256 i = 0; i < IFactory(factory).totalDeployed(); i++) {
            ( , , , bool temp) = IFactory(factory).deployInfo(i); 

            if (temp) {
                counter++;
                c[i] = int256(i);
            }
        }

        uint256[] memory allowed = new uint256[](counter);

        for (uint256 i = 0; i < allowed.length; i++) {
            
            for (uint256 j = 0; j < IFactory(factory).totalDeployed(); j++) {
                 
                if (i == 0 && c[j] >= 0) {
                    allowed[i] = j;
                    c[j] = -1;
                    break;
                }

                else if (c[j] >= 1) {
                    allowed[i] = j;
                    c[j] = -1;
                    break;
                }
            }
        }
        return allowed;
    }

    function deployCollection(DeploymentParams memory dp, Socials memory _socials) public {
        IFactory(factory).deployGumBall(dp.name, dp.symbol, dp.uris, dp.supplyBASE, dp.supplyGBT, dp.base, dp.artist, dp.delay, dp.fees);
        (address gbt, , , ) = IFactory(factory).deployInfo(IFactory(factory).totalDeployed() - 1);
        _setCollectionInfo(_socials, gbt);

        emit DeployCollection(msg.sender);
    }

    function _setCollectionInfo(Socials memory _socials, address gbtAddress) internal {
        socials[gbtAddress] = _socials;
    }

    function setCollectionInfo(Socials memory _socials, address gbtAddress) public {
        require(msg.sender == IGBT(gbtAddress).artist() || msg.sender == owner(), "!Authorized");

        socials[gbtAddress] = _socials;

        emit SetCollectionInfo(msg.sender);
    }

    function collectionPage(address[] memory gbts) public view returns (CollectionPage[] memory _cp) {

        CollectionPage[] memory cp = new CollectionPage[](gbts.length);

        for (uint256 i = 0; i < gbts.length; i++) {

            (uint256 index, address gbt, address nft, address xgbt, bool allowed) = findCollectionByAddress(gbts[i]);
            
            Socials memory col = socials[gbts[i]];
            cp[i].base.token = IGBT(gbt).BASE_TOKEN();
            cp[i].base.symbol = ERC20(cp[i].base.token).symbol();
            cp[i].base.decimals = ERC20(cp[i].base.token).decimals();
            cp[i].base.currentPrice = IGBT(gbt).currentPrice();
            cp[i].collection.artist = IGBT(gbt).artist();
            cp[i].collection.banner = col.banner;
            cp[i].collection.logo = col.logo;
            cp[i].collection.name = ERC20(gbt).name();
            cp[i].collection.symbol = ERC20(gbt).symbol();
            cp[i].collection.totalSupply = IERC20(gbt).totalSupply();
            
            //Only Arbitrum. Catch if fee doesnt exist
            try IGBT(gbt).fee() returns (uint256 gbtFee) {
                cp[i].collection.fee = [gbtFee, IGNFT(nft).bFee()];
            }catch{
                cp[i].collection.fee = [25, IGNFT(nft).bFee()];
            }

            cp[i].collection.tokenImg = col.tokenImg;
            cp[i].collection.fileExtension = col.fileExtension;
            cp[i].collection.baseImgURI = col.baseImgURI;
            cp[i].collection.socials = col.socials;
            cp[i].collection.mintableNFTs = (IGBT(gbt).initial_totalSupply() / 1e18) - (ERC721Enumerable(nft).totalSupply());
            cp[i].collection._type = col._type;
            cp[i].apr = getApr(gbt);
        }

        return cp;
    }

    function individualCollection(address gbts) public view returns (CollectionPage memory _cp) {

        CollectionPage memory cp;

        (uint256 index, address gbt, address nft, address xgbt, bool allowed) = findCollectionByAddress(gbts);
        
        Socials memory col = socials[gbt];

        cp.base.token = IGBT(gbt).BASE_TOKEN();
        cp.base.symbol = ERC20(cp.base.token).symbol();
        cp.base.decimals = ERC20(cp.base.token).decimals();
        cp.base.currentPrice = IGBT(gbt).currentPrice();
        cp.collection.artist = IGBT(gbt).artist();
        cp.collection.banner = col.banner;
        cp.collection.logo = col.logo;
        cp.collection.name = ERC20(gbt).name();
        cp.collection.symbol = ERC20(gbt).symbol();
        cp.collection.totalSupply = IERC20(gbt).totalSupply();

        //Only Arbitrum. Catch if fee doesnt exist
        try IGBT(gbt).fee() returns (uint256 gbtFee) {
            cp.collection.fee = [gbtFee, IGNFT(nft).bFee()];
        }catch{
            cp.collection.fee = [25, IGNFT(nft).bFee()];
        }

        cp.collection.tokenImg = col.tokenImg;
        cp.collection.fileExtension = col.fileExtension;
        cp.collection.baseImgURI = col.baseImgURI;
        cp.collection.socials = col.socials;
        cp.collection.mintableNFTs = (IGBT(gbt).initial_totalSupply() / 1e18) - (ERC721Enumerable(nft).totalSupply());
        cp.collection._type = col._type;
        cp.collection.tokenDeployed = gbt;
        cp.apr = getApr(gbt);

        return cp;
    }

    function getRewardTokens(address xgbt) internal view returns (address[] memory tokens) {

        uint256 counter = 0;

        for (uint256 i = 0; i < 50; i++) {

            try IXGBT(xgbt).rewardTokens(i) returns (address token) {
                counter++;
            } catch {
                break;
            }
        }

        address[] memory temp = new address[](counter);

        for (uint256 i = 0; i < counter; i++) {
            temp[i] = IXGBT(xgbt).rewardTokens(i);
        }

        return temp;
    } 

    function user_Data(address[] memory gbts, address user) public view returns (UserData[] memory userData) {

        UserData[] memory ud = new UserData[](gbts.length);

        for (uint256 i = 0; i < ud.length; i++) {
            (uint256 index, address gbt, address nft, address xgbt, ) = findCollectionByAddress(gbts[i]);
            ud[i].currentPrice = IGBT(gbt).currentPrice();

            if (user != address(0x0000000000000000000000000000000000000000)) {

                (uint256 num, uint256[] memory arr) = IXGBT(xgbt).balanceOfNFT(user);

                uint256 userBal = IERC721(nft).balanceOf(user);

                if (num != 0) {
                    ud[i].stakedNFTs = arr;
                }

                if (userBal != 0) {

                    uint256[] memory tokenIds = new uint256[](userBal);

                    for (uint256 j = 0; j < userBal; j++) {
                        tokenIds[j] = IGNFT(nft).tokenOfOwnerByIndex(user, j);
                    }

                    ud[i].unstakedNFTs = tokenIds;
                }
                
                ud[i].debt = IGBT(gbt).debt(user);
                ud[i].balanceOfBase = IERC20(IGBT(gbt).BASE_TOKEN()).balanceOf(user);
                if (ud[i].debt != 0) {
                    ud[i].ltv = 100 * IGBT(gbt).debt(user) * _gbtPerEth(gbt) / (IXGBT(xgbt).balanceOf(user));
                } else {
                    ud[i].ltv = 0;
                }
                ud[i].borrowAmountAvailable = IGBT(gbt).borrowCredit(user);
                ud[i].stakedGBTs = IXGBT(xgbt).balanceOf(user);
                ud[i].unstakedGBTs = IERC20(gbt).balanceOf(user);

                address[] memory tokens = getRewardTokens(xgbt);

                //address[] memory tokens = IXGBT(xgbt)._rewardTokens();

                Token[] memory rTokens = new Token[](tokens.length); 
                for (uint256 i = 0; i < tokens.length; i++) {
                    rTokens[i].addr = tokens[i];
                    rTokens[i].symbol = ERC20(tokens[i]).symbol();
                    rTokens[i].amount = IXGBT(xgbt).earned(user, tokens[i]);
                    rTokens[i].decimals = ERC20(tokens[i]).decimals();
                }
                ud[i].rewards.rewardTokens = rTokens;
            } else {
                uint256[] memory s = new uint256[](0);
                uint256[] memory u = new uint256[](0);
                ud[i].stakedNFTs = s;
                ud[i].unstakedNFTs = u;
                ud[i].balanceOfBase = 0;
                ud[i].debt = 0;
                ud[i].ltv = 0;
                ud[i].borrowAmountAvailable = 0;
                ud[i].stakedGBTs = 0;
                ud[i].unstakedGBTs = 0;
            }
            
            ud[i].mintableNFTs = (IGBT(gbt).initial_totalSupply() / 1e18) - (ERC721Enumerable(nft).totalSupply());
            ud[i]._type = socials[gbts[i]]._type;
            ud[i].apr = getApr(gbt);
        }
        
        return ud;
    }

    function _user_Data(address gbts, address user) internal view returns (UserData memory userData) {

        address[] memory temp = new address[](1);
        temp[0] = gbts;
        return user_Data(temp, user)[0];
    }

    function getApr(address gbt) public view returns (uint256 apr) {

        (uint256 index, address gbt, address nft, address xgbt, ) = findCollectionByAddress(gbt);
        uint256 currentPrice = IGBT(gbt).currentPrice();
        uint256 ethRewardForDuration = IXGBT(xgbt).getRewardForDuration(IGBT(gbt).BASE_TOKEN());
        uint256 gbtRewardForDuration = IXGBT(xgbt).getRewardForDuration(gbt);
        uint256 totalSupply = IXGBT(xgbt).totalSupply();

        uint256 weekly = (uint256(100) * uint256(365) / uint256(7));

        if (ethRewardForDuration == 0 || gbtRewardForDuration == 0) {
            return 0;
        } else {
            uint256 apr = (weekly * ((ethRewardForDuration * 1e18 / currentPrice) + gbtRewardForDuration) * 1e18 / totalSupply);
            return apr;
        }
    }

    function _gbtPerEth(address collection) public view returns (uint256) {
        
        uint256 GBTperETH = IGBT(collection).reserveGBT() * 1e18 / (IGBT(collection).reserveVirtualBASE() + IGBT(collection).reserveRealBASE());

        return GBTperETH;
    }

    function findCollectionByAddress(address gbt) public view returns (uint256 index, address token, address nft, address gumbar, bool allowed) {

        uint256 len = IFactory(factory).totalDeployed();

        for (uint256 i = 0; i < len; i++) {
            (address _token, address _nft, address _xgbt, bool _allowed) = IFactory(factory).deployInfo(i);

            if (_token == gbt || _nft == gbt) {
                return (i, _token, _nft, _xgbt, _allowed);
            }
        }
    }

    function userDashboard(address user) public view returns (CollectionPage[] memory, UserData[] memory) {
        
        uint256[] memory allCols = allowedCollections();
        uint256[] memory depositedCollections = new uint256[](allCols.length);
        uint256 counter = 0;

        for (uint256 i = 0; i < allCols.length; i++) {
            
            (address gbt, address gnft, address xgbt, ) = IFactory(factory).deployInfo(allCols[i]);

            if (user == IGBT(gbt).artist()) {
                depositedCollections[counter] = allCols[i];
                counter++;
            } else {
                (uint256 allBal, ) = IXGBT(xgbt).balanceOfNFT(user);
                allBal += IERC721(gnft).balanceOf(user) + IXGBT(xgbt).balanceOf(user);
                
                if (allBal + IERC20(gbt).balanceOf(user) > 0) {
                   depositedCollections[counter] = allCols[i];
                   counter++;
                }
            }
        }

        CollectionPage[] memory colInfo = new CollectionPage[](counter);
        UserData[] memory ud = new UserData[](counter);
        
        for (uint256 i = 0; i < counter; i++) {

            (address gbt, address gnft, address xgbt, ) = IFactory(factory).deployInfo(depositedCollections[i]);

            colInfo[i] = individualCollection(gbt);
            ud[i] = _user_Data(gbt, user);
        }

        return (colInfo, ud);
    }

    function TLL(address[] memory gbts) public view returns (BaseLocked[] memory) {
        BaseLocked[] memory bl = new BaseLocked[](gbts.length);

        for (uint256 i = 0; i < bl.length; i++) {
            bl[i].token = IGBT(gbts[i]).BASE_TOKEN();
            bl[i].symbol = ERC20(bl[i].token).symbol();
            bl[i].decimals = ERC20(bl[i].token).decimals();
            bl[i].lockedAmount = IERC20(bl[i].token).balanceOf(gbts[i]);
        }

        return bl;
    }
}
