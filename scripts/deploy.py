from scripts.helper import get_account, fund_with_link, get_account2
from brownie import (
    DegenDojo,
    DojoHouse,
    DojoBar,
    network,
    config,
    DojoRouter,
    interface,
)
from web3 import Web3
import yaml
import json
import os
import shutil
import time

# Set initial supply to be 10M
INITIAL_SUPPLY = Web3.toWei(3.5 * (10 ** 6), "ether")
INITIAL_REWARDS_PER_BLOCK = Web3.toWei(100, "ether")
# CHANGE BEFORE REAL DEPLOYMENT
TREASURY = "0x79d7fF3516DDB1304614B17eba085d67204C1107"
LP_AMOUNT = Web3.toWei(1.5 * (10 ** 6), "ether")
LP_ETH = Web3.toWei(15, "ether")


def deploy_degen_dojo():
    account = get_account()
    degen_dojo = DegenDojo.deploy(
        config["networks"][network.show_active()]["eth_usd_price_feed"],
        config["networks"][network.show_active()]["link_usd_price_feed"],
        config["networks"][network.show_active()]["vrf_coordinator"],
        config["networks"][network.show_active()]["link_token"],
        config["networks"][network.show_active()]["fee"],
        config["networks"][network.show_active()]["keyhash"],
        INITIAL_SUPPLY,
        INITIAL_REWARDS_PER_BLOCK,
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify"),
    )
    return degen_dojo


def deploy_dojo_bar(dojo_token):
    account = get_account()
    dojo_bar = DojoBar.deploy(
        dojo_token,
        config["networks"][network.show_active()]["router"],
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify"),
    )
    return dojo_bar


def deploy_dojo_house(dojo_bar, dojo_router):
    account = get_account()
    dojo_house = DojoHouse.deploy(
        dojo_bar,
        dojo_router,
        TREASURY,
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify"),
    )
    return dojo_house


def set_house(dojo_token, dojo_house):
    account = get_account()
    tx = dojo_token.initiateSetHouse(dojo_house, {"from": account})
    tx.wait(1)
    dojo_token.setHouse({"from": account})


def update_front_end():
    # build folder
    copy_folders_to_front_end("./build", "../front/front_end/src/chain-info")
    with open("brownie-config.yaml", "r") as brownie_config:
        config_dict = yaml.load(brownie_config, Loader=yaml.FullLoader)
        with open(
            "../front/front_end/src/brownie-config.json", "w"
        ) as brownie_config_json:
            json.dump(config_dict, brownie_config_json)
    print("Front end updated")


def copy_folders_to_front_end(src, dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)


def deploy_dojo_router(dojo_token):
    account = get_account()
    dojo_router = DojoRouter.deploy(
        dojo_token,
        config["networks"][network.show_active()]["factory"],
        config["networks"][network.show_active()]["weth"],
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify"),
    )
    return dojo_router


def approve_erc20(amount, spender, erc20_address, account):
    print("Approving ERC20 token...")
    erc20 = interface.IERC20(erc20_address)
    tx = erc20.approve(spender, amount, {"from": account})
    tx.wait(1)
    print("Approved!")
    return tx


def add_lp(dojo_token):
    account = get_account()
    uniswap_router = interface.IUniswapV2Router02(
        config["networks"][network.show_active()].get("router")
    )
    approve_erc20(LP_AMOUNT, uniswap_router, dojo_token, account)
    tx = uniswap_router.addLiquidityETH(
        dojo_token,
        LP_AMOUNT,
        0,
        0,
        account,
        time.time() * 10,
        {"from": account, "value": LP_ETH},
    )
    print("Adding DOJO Liquidity to Uniswap")


def add_router(dojo_token, dojo_router):
    account = get_account()
    print("Adding Router to whitelist")
    tx = dojo_token.addRouter(dojo_router, {"from": account})
    tx.wait(1)


def main():

    dojo_token = deploy_degen_dojo()
    # add liquidity to uniswap
    add_lp(dojo_token)
    fund_with_link(dojo_token)
    dojo_bar = deploy_dojo_bar(dojo_token)
    dojo_house = deploy_dojo_house(dojo_bar, dojo_token)
    dojo_router = deploy_dojo_router(dojo_token)
    # add the router to whitelisted
    add_router(dojo_token, dojo_router)
    # set house
    set_house(dojo_token, dojo_house)

    update_front_end()
