import sqlite3
from threading import Lock

from config import DB_NAME

def sync (lock):
    def function (f):
        def wrapper (*args, **kargs):
            lock.acquire ()
            try:
                return f(*args, **kargs)
            finally: # exec in all cases
                lock.release ()
        return wrapper
    return function

def singleton(class_):
    instances = {}
    def getinstance(*args, **kwargs):
        if class_ not in instances:
            instances[class_] = class_(*args, **kwargs)
        return instances[class_]
    return getinstance

myLock = Lock()

@singleton
class Storage:
    def __init__(self):
        self.connection = sqlite3.connect(DB_NAME, check_same_thread=False)
        self.init_tables()

    def close(self):
        self.connection.close()
    
    @sync(myLock)
    def set_contract_checked(self, address:str, chain_id:str, detector:str):
        cursor = self.connection.cursor()
        cursor.execute('SELECT id from detectors where name = ?', (detector,))
        row = cursor.fetchone()
        if row is None:
            cursor_used = cursor.execute('INSERT INTO detectors (name) VALUES (?)', (detector,))
            detector_id = cursor_used.lastrowid
        else:
            detector_id = row[0]
        try:
            cursor_used = cursor.execute('INSERT INTO contracts (address, chain_id) VALUES (?, ?)', (address, chain_id))
            contract_id = cursor_used.lastrowid
        except sqlite3.IntegrityError as e:
            cursor.execute('SELECT id from contracts where address = ? and chain_id = ?', (address, chain_id))
            row = cursor.fetchone()
            contract_id = row[0]

        cursor_used = cursor.execute('INSERT OR IGNORE INTO contracts_checked (contract_id, detector_id) VALUES (?, ?)', (contract_id, detector_id))
        self.connection.commit()

    def init_tables(self):
        cursor = self.connection.cursor()

        #create detectors table
        #create contracts table
        #create contracts to detectors relation table
        cursor.executescript('''
        CREATE TABLE IF NOT EXISTS detectors (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_detector ON detectors (name);
        CREATE TABLE IF NOT EXISTS contracts (
        id INTEGER PRIMARY KEY,
        address TEXT NOT NULL,
        chain_id TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_contract ON contracts (address, chain_id);
        CREATE TABLE IF NOT EXISTS contracts_checked (
        contract_id INTEGER,
        detector_id INTEGER,
        ts_checked TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
        FOREIGN KEY (contract_id)  REFERENCES contracts (id),
        FOREIGN KEY (detector_id)  REFERENCES detectors (id)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_contract_detector ON contracts_checked (contract_id, detector_id);
        ''')
        self.connection.commit()
    
    @sync(myLock)
    def get_contract_detectors(self, address:str, chain_id:str):
        cursor = self.connection.cursor()
        cursor.execute('''
        SELECT 
            detectors.name
        FROM 
            contracts_checked join
            contracts ON contracts_checked.contract_id = contracts.id join
            detectors ON contracts_checked.detector_id = detectors.id
        WHERE
            contracts.address = ? AND contracts.chain_id = ?
        ''', (address, chain_id))
        results = cursor.fetchall()
        return [row[0] for row in results]


