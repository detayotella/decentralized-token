// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "../src/ERC20.sol";
import {DepositorCoin} from "../src/DepositorCoin.sol";
import {Oracle} from "../src/Oracle.sol";

contract StableCoin is ERC20 {
    DepositorCoin public depositorCoin;
    Oracle public oracle; 
    uint256 public feeRatePercentage; 

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _decimals,
        Oracle _oracle, 
        uint256 _feeRatePercentage
    ) ERC20(_name, _symbol, _decimals) {
        oracle = _oracle;
        feeRatePercentage = _feeRatePercentage; 

    }

    function mint() external payable {
        uint fee = _getFee(msg.value);
        uint256 mintStableCoinAmount = (msg.value - fee) * oracle.getPrice();

        _mint(msg.sender, mintStableCoinAmount);
    }

    function burn(uint256 burnStablecoinAmount) external {
        _burn(msg.sender, burnStablecoinAmount);

        uint256 refundingEth = burnStablecoinAmount / oracle.getPrice();

        uint256 fee = _getFee(refundingEth); 

        (bool success, ) = msg.sender.call{value: (refundingEth - fee)}("");
        require(success, "STC: Burn refund transaction failed");
    }

    function _getFee(uint256 ethAmount) private view returns (uint256) {
        return (ethAmount * feeRatePercentage) / 100; 
    }

    function depositCollateralBuffer() external payable {
        int256 deficitOrSurplusInUsd = _getDeficitOrSurplusInContractInUsd();

        uint256 usdInDpcPrice; 
        uint256 addedSurplusEth; 

        if (deficitOrSurplusInUsd <= 0) {
            uint256 deficitInUsd = uint256(deficitOrSurplusInUsd * -1);
            uint256 deficitInEth = deficitInUsd / oracle.getPrice();
            
            addedSurplusEth = msg.value - deficitInEth; 

            depositorCoin = new DepositorCoin("Depositor Coin", "DPC"); 
            // new surplus: msg.value * oracle.getPrice();

            usdInDpcPrice = 1; 
        } else {
            usdInDpcPrice = depositorCoin.totalSupply() / deficitOrSurplusInUsd;
            addedSurplusEth = msg.value; 
        }
        

        uint256 mintDepositorCoinAmount = addedSurplusEth * oracle.getPrice() * usdInDpcPrice;
        depositorCoin.mint(msg.sender, mintDepositorCoinAmount);
    }

    function withdrawCollateralBuffer(uint256 burnDepositorCoinAmount) external {
        int256 deficitOrSurplusInUsd = _getDeficitOrSurplusInContractInUsd();  
        require(deficitOrSurplusInUsd > 0, "STC: No depositor funds to withdraw");

        uint256 surplusInUsd = uint256(deficitOrSurplusInUsd);

        depositorCoin.burn(msg.sender, burnDepositorCoinAmount); 

        // usdInDpcPrice = 250 / 500 = 0.5 
        uint256 usdInDpcPrice = depositorCoin.totalSupply() / deficitOrSurplusInUsd; 
      
        // 125 / 0.5 = 250 
        uint256 refundingUsd = burnDepositorCoinAmount / usdInDpcPrice; 
        
        // 250 / 1000 = 0.25 ETH 
        uint256 refundingEth = refundingUsd / oracle.getPrice(); 

        (bool success, ) = msg.sender.call{value: refundingEth}(""); 
        require(success, "STC: Withdraw collateral buffer transaction failed"); 
    }

    function _getDeficitOrSurplusInContractInUsd() private view returns (int256) { 
        uint256 ethContractBalanceInUsd = (address(this).balance - msg.value) * oracle.getPrice(); 

        uint256 totalStableCoinBalanceInUsd = totalSupply; 

        int256 surplusOrDeficit = int256(ethContractBalanceInUsd) - int256(totalStableCoinBalanceInUsd); 

        return surplusOrDeficit; 
         
    }
}
