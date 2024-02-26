from datetime import datetime
import time
import click
import subprocess
import logging

from sheet import Sheet
from config import LOGGING_LEVEL

DETECTOR_COL_NUM = 2

def get_slitherin_version():
    command = ['slitherin', '--version']
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True, encoding="utf8")
        return result.stdout.split('\n')[0].strip()
    except Exception as e:
        return ''

def save_sheet(results, service_account, sheet_id, list_name, slitherin_version):
    logger = logging.getLogger()
    logger.info("save results for %d detectors to list %s", len(results), list_name)
    print(results)
    sheet = Sheet(service_account, sheet_id, list_name)
    values = sheet.get_rows("A1:ZZZ")
    detector_names = values[0][DETECTOR_COL_NUM:]

    detector_col_by_name = {detector_names[i]:(i+DETECTOR_COL_NUM) for i in range(0, len(detector_names))}
    new_row = [round(time.time()), slitherin_version] + ['']*len(detector_names)
    new_columns = []
    for detector_name in results:
        if detector_name in detector_col_by_name:
            new_row[detector_col_by_name[detector_name]] = results[detector_name]
        else:
            new_columns.append([detector_name]+['']*(len(values)-1)+[results[detector_name]])

    response = sheet.add_row(new_row)
    last_column_num = DETECTOR_COL_NUM + len(detector_names) - 1
    for column in new_columns:
        last_column_num += 1
        sheet.add_column(last_column_num, column)

@click.command()
@click.option('-i', '--input', help="file with benchmark results", required=True)
@click.option('-sa', '--service-account', help="google service account json file", required=True)
@click.option('-si', '--sheet-id', help="google sheet id", required=True)
@click.option('-ln', '--list-name', help="google list name", required=True)
@click.option('-sv', '--slitherin-version', help="slitherin version, default value taken from slitherin --version command", required=False, default=get_slitherin_version())
def main(input, service_account, sheet_id, list_name, slitherin_version):
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s: %(asctime)s - %(process)s - %(message)s"))

    logger = logging.getLogger()
    logger.setLevel(LOGGING_LEVEL)
    logger.addHandler(handler)
    with open(input, 'r') as f:
        detector_results = {}
        for line in f:
            line_list = line.strip().split(';')
            stat_type, c = line_list[0], line_list[1:]

            if stat_type == '':
                detector_names = c
                continue
            detector_results[stat_type] = dict(zip(detector_names, c))
        for stat_type in detector_results:
            save_sheet(detector_results[stat_type], service_account, sheet_id, f"{list_name}_{stat_type}", slitherin_version)

if __name__ == "__main__":
    main()

