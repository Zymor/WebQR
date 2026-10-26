import 'dart:io';
import 'package:qr/qr.dart';

void main(List<String> args) {
  final base = args.isEmpty ? 'https://afterwork-livid.vercel.app' : args.first;
  final folder = Directory('qr-codes/public')..createSync(recursive:true);
  for (var i=1;i<=5;i++) {
    final id='T${i.toString().padLeft(2,'0')}';
    final url='$base/#/Table:$id';
    final matrix=QrImage(QrCode.fromData(data:url,errorCorrectLevel:QrErrorCorrectLevel.M));
    final side=matrix.moduleCount+8;
    final modules=StringBuffer();
    for(var r=0;r<matrix.moduleCount;r++) {
      for(var c=0;c<matrix.moduleCount;c++) {
        if(matrix.isDark(r,c)) modules.write('<rect x="${c+4}" y="${r+4}" width="1" height="1"/>');
      }
    }
    File('${folder.path}/after-work-$id.svg').writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $side $side" shape-rendering="crispEdges"><title>After Work Table $id</title><desc>$url</desc><rect width="$side" height="$side" fill="white"/><g fill="black">$modules</g></svg>');
    stdout.writeln('$id: $url');
  }
}
