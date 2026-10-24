"""Exercise the actual interactive Bash menu through a pseudo-terminal."""
import errno,os,pty,select,shutil,subprocess,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class MenuTests(unittest.TestCase):
    def run_menu(self,keys):
        with tempfile.TemporaryDirectory() as tmp:
            config=Path(tmp)/'config';shutil.copytree(ROOT/'config.example',config)
            master,slave=pty.openpty()
            env={**os.environ,'NIK_CONFIG':str(config),'NIK_STATE':str(Path(tmp)/'state'),'NIK_COLOR':'never','NIK_WIDTH':'60'}
            process=subprocess.Popen(['bash',str(ROOT/'nik.sh'),'menu'],stdin=slave,stdout=slave,stderr=slave,env=env)
            os.close(slave);output=b''
            try:
                os.write(master,keys.encode())
                deadline=time.monotonic()+15
                while time.monotonic()<deadline:
                    ready,_,_=select.select([master],[],[],0.1)
                    if ready:
                        try:chunk=os.read(master,65536)
                        except OSError as error:
                            if error.errno==errno.EIO:break
                            raise
                        if not chunk:break
                        output+=chunk
                    elif process.poll() is not None:break
                process.wait(timeout=2)
                self.assertEqual(process.returncode,0,output.decode(errors='replace'))
                self.assertFalse((Path(tmp)/'state').exists())
                return output.decode(errors='replace')
            finally:
                if process.poll() is None:process.kill();process.wait()
                os.close(master)
    def test_player_menu_exit(self):
        text=self.run_menu('1\n0\n');self.assertIn('wspólna przygoda',text);self.assertIn('Dla Franka',text)
    def test_countdown_preview_and_return(self):
        text=self.run_menu('1\n3\n3\n2\nStart zabawy ♥\n2\n\n0\n')
        self.assertIn('title PlayerOne title',text);self.assertIn('Start zabawy ♥',text);self.assertIn('podgląd',text)
    def test_cancel_command_and_change_player(self):
        text=self.run_menu('1\n3\n1\nCześć ♥\n0\n6\n2\n0\n')
        self.assertIn('Gracz: gracz2',text);self.assertNotIn('[podgląd] title',text)
    def test_literal_shell_metacharacters_are_not_executed(self):
        text=self.run_menu('1\n3\n1\n$(touch /tmp/nik-menu-MUST-NOT-EXIST)\n2\n\n0\n')
        self.assertIn('$(touch /tmp/nik-menu-MUST-NOT-EXIST)',text)
        self.assertFalse(Path('/tmp/nik-menu-MUST-NOT-EXIST').exists())
    def test_bad_input_recovers(self):
        text=self.run_menu('1\n99\n1\n1\nunknown\n1\n1\n\n0\n')
        self.assertIn('Wybierz numer',text);self.assertIn('Komenda zakończona błędem',text)

if __name__=='__main__':unittest.main()
