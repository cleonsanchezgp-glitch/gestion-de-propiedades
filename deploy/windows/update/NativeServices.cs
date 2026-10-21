using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Aelium.Update {
    public struct ActionInfo { public uint Type; public uint Delay; }
    public class ServiceOptions {
        public uint StartType;
        public bool DelayedAutoStart;
        public uint ResetPeriod;
        public bool NonCrashFailures;
        public ActionInfo[] Actions;
    }
    public static class NativeServices {
        [StructLayout(LayoutKind.Sequential)] struct Failures {public uint Reset;public IntPtr Reboot;public IntPtr Command;public uint Count;public IntPtr Actions;}
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string machine,string database,uint access);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,uint access);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool CloseServiceHandle(IntPtr handle);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryServiceConfig(IntPtr service,IntPtr buffer,uint size,out uint needed);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryServiceConfig2(IntPtr service,uint level,IntPtr buffer,uint size,out uint needed);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ChangeServiceConfig2(IntPtr service,uint level,IntPtr info);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ChangeServiceConfig(IntPtr service,uint type,uint start,uint error,string path,string group,IntPtr tag,string dependencies,string account,string password,string display);
        static IntPtr Handle(string name,uint access) {
            if (name!="AeliumAPI" && name!="AeliumKeycloak" && name!="AeliumTunnel") throw new InvalidOperationException("Not a writer service.");
            IntPtr manager=OpenSCManager(null,null,1);
            if(manager==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {IntPtr service=OpenService(manager,name,access);if(service==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());return service;}finally{CloseServiceHandle(manager);}
        }
        static IntPtr Query(IntPtr service,uint level) {
            uint needed;
            if(level==0) QueryServiceConfig(service,IntPtr.Zero,0,out needed);else QueryServiceConfig2(service,level,IntPtr.Zero,0,out needed);
            if(needed==0 || needed>65536) throw new InvalidOperationException("Cannot inspect service options.");
            IntPtr buffer=Marshal.AllocHGlobal((int)needed);
            bool ok=level==0?QueryServiceConfig(service,buffer,needed,out needed):QueryServiceConfig2(service,level,buffer,needed,out needed);
            if(!ok){Marshal.FreeHGlobal(buffer);throw new Win32Exception(Marshal.GetLastWin32Error());}return buffer;
        }
        public static ServiceOptions Read(string name) {
            IntPtr service=Handle(name,1);
            try {
                ServiceOptions options=new ServiceOptions();IntPtr buffer=Query(service,0);
                try{options.StartType=(uint)Marshal.ReadInt32(buffer,4);}finally{Marshal.FreeHGlobal(buffer);}
                buffer=Query(service,3);try{options.DelayedAutoStart=Marshal.ReadInt32(buffer)!=0;}finally{Marshal.FreeHGlobal(buffer);}
                buffer=Query(service,4);try{options.NonCrashFailures=Marshal.ReadInt32(buffer)!=0;}finally{Marshal.FreeHGlobal(buffer);}
                buffer=Query(service,2);
                try {
                    Failures f=(Failures)Marshal.PtrToStructure(buffer,typeof(Failures));
                    if(!String.IsNullOrEmpty(Marshal.PtrToStringUni(f.Command)) || !String.IsNullOrEmpty(Marshal.PtrToStringUni(f.Reboot)) || f.Count>32) throw new InvalidOperationException("Custom recovery requires a separate plan.");
                    options.ResetPeriod=f.Reset;options.Actions=new ActionInfo[f.Count];
                    for(int i=0;i<f.Count;i++){options.Actions[i]=(ActionInfo)Marshal.PtrToStructure(IntPtr.Add(f.Actions,i*8),typeof(ActionInfo));if(options.Actions[i].Type>1)throw new InvalidOperationException("Custom recovery requires a separate plan.");}
                }finally{Marshal.FreeHGlobal(buffer);}
                return options;
            }finally{CloseServiceHandle(service);}
        }
        static void Flag(IntPtr service,uint level,bool value) {
            IntPtr buffer=Marshal.AllocHGlobal(4);try{Marshal.WriteInt32(buffer,value?1:0);if(!ChangeServiceConfig2(service,level,buffer))throw new Win32Exception(Marshal.GetLastWin32Error());}finally{Marshal.FreeHGlobal(buffer);}
        }
        public static void Write(string name,ServiceOptions options) {
            if(options.StartType<2 || options.StartType>4 || options.Actions==null || options.Actions.Length>32)throw new InvalidOperationException("Invalid service options.");
            IntPtr service=Handle(name,2|16),actions=IntPtr.Zero,buffer=IntPtr.Zero;
            try {
                actions=Marshal.AllocHGlobal(Math.Max(1,options.Actions.Length*8));
                for(int i=0;i<options.Actions.Length;i++){if(options.Actions[i].Type>1)throw new InvalidOperationException("Unsupported recovery action.");Marshal.StructureToPtr(options.Actions[i],IntPtr.Add(actions,i*8),false);}
                // Non-null actions pointer with zero count explicitly removes old actions.
                Failures failures=new Failures{Reset=options.ResetPeriod,Count=(uint)options.Actions.Length,Actions=actions,Reboot=IntPtr.Zero,Command=IntPtr.Zero};
                buffer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Failures)));Marshal.StructureToPtr(failures,buffer,false);
                if(!ChangeServiceConfig2(service,2,buffer))throw new Win32Exception(Marshal.GetLastWin32Error());
                Flag(service,4,options.NonCrashFailures);
                if(!ChangeServiceConfig(service,UInt32.MaxValue,options.StartType,UInt32.MaxValue,null,null,IntPtr.Zero,null,null,null,null))throw new Win32Exception(Marshal.GetLastWin32Error());
                Flag(service,3,options.DelayedAutoStart);
            }finally{if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);if(actions!=IntPtr.Zero)Marshal.FreeHGlobal(actions);CloseServiceHandle(service);}
        }
    }
}
